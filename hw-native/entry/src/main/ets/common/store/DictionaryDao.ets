/**
 * 字典缓存（分类 / 支付方式）。
 *
 * 为什么必须缓存：离线时流水行要显示「分类名 + 分类色 + 支付方式名」，
 * 而这些都不在 expenses 表里（表里只有 id）。不缓存字典，断网后整列表会变成一堆空名字。
 *
 * 颜色规则与 Web 一致：**显式 color 优先，没设过才按 id 哈希**。
 * 二级分类的颜色跟一级走 —— 所以写入时二级存父级的 color（服务端已归一化）。
 */
import { relationalStore } from '@kit.ArkData';

import { Db } from './Db';
import { CategoryNode, PaymentMethodItem } from '../net/Api';

export interface CachedCategory {
  id: string;
  name: string;
  icon: string;
  color: string;
  parentId: string;
}

export class DictionaryDao {
  static async cacheCategories(categories: CategoryNode[]): Promise<void> {
    const store = Db.get();
    for (const root of categories) {
      await DictionaryDao.putCategory(root, null);
      for (const child of root.children) {
        // 二级的颜色跟一级走：服务端已把父色给到 child.color；空则用父的
        const childColor = child.color !== '' ? child.color : root.color;
        await DictionaryDao.putCategory(child, root.id === child.parentId ? root : null, childColor);
      }
    }
  }

  static async cachePayments(payments: PaymentMethodItem[]): Promise<void> {
    const store = Db.get();
    for (const p of payments) {
      const bucket: relationalStore.ValuesBucket = {
        'id': p.id,
        'name': p.name,
        'type': p.type,
        'icon': p.icon,
        'billing_day': p.billingDay ?? 0,
        'repayment_day': p.repaymentDay ?? 0,
        'is_enabled': p.isEnabled ? 1 : 0,
        'sort_order': p.sortOrder
      };
      await store.insert('payment_methods', bucket, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
    }
  }

  /**
   * 从本地缓存**还原分类树**（离线记账用）。
   *
   * 记账抽屉需要完整的 `CategoryNode[]`（一级 + 二级）才能选分类。
   * 原来 `loadDict()` 只走接口，离线时整棵树是空的 → 选不了分类 → 记不了账，
   * 尽管缓存表里明明有全部数据。这个方法是那条回退路径。
   */
  static async categoriesTree(): Promise<CategoryNode[]> {
    const store = Db.get();
    const rs = await store.querySql(
      'SELECT id, parent_id, name, depth, icon, color, sort_order, is_enabled FROM categories ORDER BY sort_order, id'
    );
    const all: CategoryNode[] = [];
    while (rs.goToNextRow()) {
      const parentIdx = rs.getColumnIndex('parent_id');
      const parentId = rs.isColumnNull(parentIdx) ? null : rs.getString(parentIdx);
      all.push({
        id: rs.getString(rs.getColumnIndex('id')),
        parentId: parentId,
        name: rs.getString(rs.getColumnIndex('name')),
        depth: rs.getLong(rs.getColumnIndex('depth')),
        icon: rs.getString(rs.getColumnIndex('icon')),
        color: rs.getString(rs.getColumnIndex('color')),
        sortOrder: rs.getLong(rs.getColumnIndex('sort_order')),
        isEnabled: rs.getLong(rs.getColumnIndex('is_enabled')) === 1,
        expenseCount: 0,
        children: []
      });
    }
    rs.close();
    const roots: CategoryNode[] = [];
    for (const node of all) {
      if (node.parentId === null) {
        roots.push(node);
      }
    }
    for (const root of roots) {
      for (const node of all) {
        if (node.parentId === root.id) {
          root.children.push(node);
        }
      }
    }
    return roots;
  }

  /** 从本地缓存还原支付方式列表（离线记账用） */
  static async paymentsList(): Promise<PaymentMethodItem[]> {
    const store = Db.get();
    const rs = await store.querySql(
      'SELECT id, name, type, icon, billing_day, repayment_day, is_enabled, sort_order FROM payment_methods ORDER BY sort_order, id'
    );
    const out: PaymentMethodItem[] = [];
    while (rs.goToNextRow()) {
      const billing = rs.getLong(rs.getColumnIndex('billing_day'));
      const repayment = rs.getLong(rs.getColumnIndex('repayment_day'));
      out.push({
        id: rs.getString(rs.getColumnIndex('id')),
        name: rs.getString(rs.getColumnIndex('name')),
        type: rs.getString(rs.getColumnIndex('type')),
        icon: rs.getString(rs.getColumnIndex('icon')),
        billingDay: billing > 0 ? billing : null,
        repaymentDay: repayment > 0 ? repayment : null,
        isEnabled: rs.getLong(rs.getColumnIndex('is_enabled')) === 1,
        sortOrder: rs.getLong(rs.getColumnIndex('sort_order')),
        expenseCount: 0
      });
    }
    rs.close();
    return out;
  }

  /** 记录人列表（本地缓存；流水筛选与归属显示用） */
  static async owners(): Promise<CachedCategory[]> {
    const rs = await Db.get().querySql('SELECT id, display_name FROM users ORDER BY display_name, id');
    const out: CachedCategory[] = [];
    while (rs.goToNextRow()) {
      out.push({
        id: rs.getString(rs.getColumnIndex('id')),
        name: rs.getString(rs.getColumnIndex('display_name')),
        icon: '',
        color: '',
        parentId: ''
      });
    }
    rs.close();
    return out;
  }

  /** 写用户缓存（快照用） */
  static async cacheUsers(items: CachedCategory[]): Promise<void> {
    const store = Db.get();
    for (const u of items) {
      const bucket: relationalStore.ValuesBucket = {
        'id': u.id,
        'display_name': u.name,
        'role': 'member',
        'updated_at': new Date().toISOString()
      };
      await store.insert('users', bucket, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
    }
  }

  /** 分类名映射（离线行显示用） */
  static async categoryNames(): Promise<Map<string, CachedCategory>> {
    const store = Db.get();
    const rs = await store.querySql('SELECT id, name, icon, color, parent_id FROM categories');
    const out: Map<string, CachedCategory> = new Map<string, CachedCategory>();
    while (rs.goToNextRow()) {
      const id = rs.getString(rs.getColumnIndex('id'));
      out.set(id, {
        id: id,
        name: rs.getString(rs.getColumnIndex('name')),
        icon: rs.getString(rs.getColumnIndex('icon')),
        color: rs.getString(rs.getColumnIndex('color')),
        parentId: rs.getString(rs.getColumnIndex('parent_id'))
      });
    }
    rs.close();
    return out;
  }

  /** 支付方式名映射 */
  static async paymentNames(): Promise<Map<string, string>> {
    const store = Db.get();
    const rs = await store.querySql('SELECT id, name FROM payment_methods');
    const out: Map<string, string> = new Map<string, string>();
    while (rs.goToNextRow()) {
      out.set(rs.getString(rs.getColumnIndex('id')), rs.getString(rs.getColumnIndex('name')));
    }
    rs.close();
    return out;
  }

  private static async putCategory(
    cat: CategoryNode,
    parent: CategoryNode | null,
    colorOverride: string = ''
  ): Promise<void> {
    const store = Db.get();
    const color = colorOverride !== '' ? colorOverride : (parent === null ? cat.color : parent.color);
    const bucket: relationalStore.ValuesBucket = {
      'id': cat.id,
      'parent_id': cat.parentId,
      'name': cat.name,
      'depth': cat.depth,
      'icon': cat.icon,
      'color': color,
      'sort_order': cat.sortOrder,
      'is_enabled': cat.isEnabled ? 1 : 0
    };
    await store.insert('categories', bucket, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }
}

/**
 * 记住上次用的分类与支付方式（H3）。
 *
 * 记账是高频动作，绝大多数时候重复的是同一组选择；每次都从第一项重选，
 * 等于每天多做两次没有信息量的点击。
 *
 * 沿用前必须校验「它现在仍然可选」——分类可能已被停用。
 * 这条校验由调用方做（它手上有字典），这里只负责存取。
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const STORE = 'suenmoney';
const KEY = 'suenmoney:last-pick';

export interface LastPickValue {
  categoryId: string;
  paymentMethodId: string;
}

export class LastPick {
  private static store: preferences.Preferences | null = null;

  static async init(context: common.Context): Promise<void> {
    try {
      LastPick.store = await preferences.getPreferences(context, STORE);
    } catch (e) {
      LastPick.store = null;
    }
  }

  static async read(): Promise<LastPickValue | null> {
    if (LastPick.store === null) {
      return null;
    }
    try {
      const raw = LastPick.store.getSync(KEY, '') as string;
      if (raw === '') {
        return null;
      }
      const parsed = JSON.parse(raw) as LastPickValue;
      if (parsed.categoryId === undefined || parsed.paymentMethodId === undefined) {
        return null;
      }
      return parsed;
    } catch (e) {
      return null;
    }
  }

  static async write(value: LastPickValue): Promise<void> {
    if (LastPick.store === null) {
      return;
    }
    try {
      LastPick.store.putSync(KEY, JSON.stringify(value));
      await LastPick.store.flush();
    } catch (e) {
      // 写失败只影响下次默认值，不影响本次记账
    }
  }
}

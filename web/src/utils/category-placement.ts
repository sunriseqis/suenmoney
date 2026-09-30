/**
 * 导入时「只有一个分类名」的落位推断（纯函数，便于单测）。
 *
 * 背景：suenmoney 对账 CSV 的「分类 / 二级分类」两列里，绝大多数行只填了一列 ——
 * 真实数据 3228 行中 2777 行的「二级分类」为空，叶子名（堂食外卖 / 日用百货 …）
 * 直接写在「分类」列，只有 451 行同时填了一级与二级。若看到「只有一个名字」就
 * 无条件建成一级分类，这些叶子会被全部错误地提升为顶级分类，层级彻底错乱；
 * 而同一批数据里那 451 行恰好提供了「叶子 → 父级」的完整证据。
 *
 * 因此这里不做「无条件建根」，而是按证据强弱决定：能证明它已存在就认领，
 * 能证明它是二级就挂到父下，什么都没有才退而求其次建一级。
 *
 * 本文件刻意不 import IDB / store / API —— 只做纯决策，创建动作由调用方执行，
 * 这样才能用 node:test 直接覆盖各种证据组合。
 */

export interface PlacementInput {
  /** 计划项里的一级名（可能为空串） */
  parent: string;
  /** 计划项里的二级名（可能为空串） */
  child: string;
  /** 二级名 → 一级名（来自现有字典 + CSV 里同时有两列的行） */
  knownChildToParent: Map<string, string>;
  /** 现有字典里的一级名 */
  knownRoots: Set<string>;
  /** 现有字典里的二级名 */
  knownChildren: Set<string>;
}

export type Placement =
  | { kind: 'existing'; categoryName: string }
  | { kind: 'createChild'; parentName: string; childName: string }
  | { kind: 'createRoot'; name: string };

/** 「只有一个名字」时的证据推断：先认领、再找父，最后才兜底建根。 */
function placeSingleName(name: string, input: PlacementInput): Placement {
  // a. 它本来就是某个一级下的二级 → 直接认领，避免又建一个同名二级造成重复
  if (input.knownChildren.has(name)) return { kind: 'existing', categoryName: name };
  // b. 它本来就是一级 → 直接认领（先于 knownChildToParent 判断，避免「已知一级」被误判成二级）
  if (input.knownRoots.has(name)) return { kind: 'existing', categoryName: name };
  // c. 有证据表明它是二级，只是原始数据没写全父名 → 挂到证据给出的父下
  const parentName = input.knownChildToParent.get(name);
  if (parentName !== undefined) return { kind: 'createChild', parentName, childName: name };
  // d. 没有任何证据 → 只能建一级（最后的兜底，调用方会把这些名字告诉用户去设置里手改）
  return { kind: 'createRoot', name };
}

export function decidePlacement(input: PlacementInput): Placement {
  // 1. 父子都有：直接按父子关系建二级。父为空时不能贸然建子，退回按「只有一个名字」处理 child。
  if (input.child !== '' && input.parent !== '') {
    return { kind: 'createChild', parentName: input.parent, childName: input.child };
  }
  // 2. 只有一个名字：子为空看 parent，父为空看 child，统一走证据推断。
  const name = input.child !== '' ? input.child : input.parent;
  return placeSingleName(name, input);
}

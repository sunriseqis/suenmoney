import { badRequest } from '../lib/http-error.ts';

/**
 * 把总额等额拆成每期金额。
 *
 * **前 n−1 期取整，最后一期补足差额**，保证各期之和**恰好**等于总额。
 *
 * 为什么必须这样做：¥1000 分 3 期，若每期各自四舍五入成 333.33，三期之和是
 * 999.99 —— 账面上凭空少了一分钱，而且少掉的这一分会永远留在「剩余未付」里，
 * 让分期永远无法结清。这不是凑数，是分期在会计上的标准做法。
 *
 * 上界 600 期（50 年）是防呆：期数填错一个数量级会生成几千条待办，
 * 而清理它们比拦住这次输入麻烦得多。
 */
export function splitInstallment(totalCents: number, periods: number): number[] {
  if (!Number.isInteger(totalCents) || totalCents <= 0) {
    throw badRequest('分期总额必须是正整数（单位：分）');
  }
  if (!Number.isInteger(periods) || periods < 1 || periods > 600) {
    throw badRequest('期数必须在 1–600 之间');
  }
  if (totalCents < periods) {
    // 否则会出现金额为 0 的期，而 amount_cents > 0 是数据库的硬约束
    throw badRequest(`总额太小，无法分成 ${periods} 期（每期至少 1 分）`);
  }

  const base = Math.floor(totalCents / periods);
  const amounts = Array.from({ length: periods }, () => base);
  amounts[periods - 1] = totalCents - base * (periods - 1);

  return amounts;
}

// ⚠ 由 scripts/gen-tokens.mjs 从 docs/design/tokens.json 生成，请勿手改。
// 计划三 S0 时搬进 hw/entry/src/main/ets/common/Tokens.ets。
export class DesignTokens {
  // 表面
  static readonly surface: string = '#141222';
  static readonly surfaceContainer: string = '#1E1D2E';
  static readonly surfaceHigh: string = '#282740';
  // 文字
  static readonly onSurface: string = '#F2EFFA';
  static readonly onSurfaceVariant: string = '#B9B5CC';
  // 描边
  static readonly outline: string = '#3A3852';
  static readonly outlineStrong: string = '#706D96';
  // 五色
  static readonly primary: string = '#B388FF';
  static readonly onPrimary: string = '#2A1065';
  static readonly secondary: string = '#4DFFD2';
  static readonly onSecondary: string = '#00352E';
  static readonly tertiary: string = '#FF7AB8';
  static readonly onTertiary: string = '#5F1606';
  static readonly lemon: string = '#E5FF41';
  static readonly onLemon: string = '#3F2E00';
  static readonly info: string = '#5DB8FF';
  static readonly onInfo: string = '#00344F';

  // 圆角 / 间距
  static readonly radiusCard: number = 24;
  static readonly radiusField: number = 14;
  static readonly radiusPill: number = 999;
  static readonly grid: number = 8;
}

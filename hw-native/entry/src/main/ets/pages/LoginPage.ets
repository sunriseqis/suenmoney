/**
 * 登录页（H1）。
 *
 * 与 Web 一致的三件事：
 *   1. 登录与「首次初始化」共用一张表单 —— 首次部署的用户还没有账号，
 *      直接给「登录」会让他以为要用别人的账号。
 *   2. 服务器地址只在这里出现（多地址 + 顺序探活 + 4s 快失败）。
 *   3. 错误按类型说人话：口令错就说口令错，别把 401 说成「网络不好」。
 */


import { router } from '@kit.ArkUI';
import { AuthStore } from '../common/auth/AuthStore';
import { ApiError } from '../common/net/ApiError';
import { ServerConfig } from '../common/net/ServerConfig';
import { ProbeResult, ServerRouter } from '../common/net/ServerRouter';
import { THEME_STORAGE_KEY, ThemeManager } from '../common/theme/ThemeManager';
import { radiusOf, outlineStrongOf } from '../common/ui/UiStyle';
import { CANDY, CYBER, ThemeTokens } from '../common/theme/AppTheme';
import { displayFont, bodyFont } from '../common/theme/Fonts';
import { ensureFonts } from '../common/theme/FontRegistry';

@Entry
@Component
struct LoginPage {
  /** 订阅全局主题名：切换后本屏立即重绘（不能存 tokens 快照，见 ThemeManager 注释） */
  @StorageLink(THEME_STORAGE_KEY) themeName: string = ThemeManager.get().name;
  @State username: string = '';
  @State password: string = '';
  /** R98：三个固定槽（空表示未配置） */
  @State slots: string[] = ['', '', ''];
  /** 每槽连通状态：'' 未测 / 'ok' 通 / 'bad' 不通 */
  @State probeStates: string[] = ['', '', ''];
  @State newServer: string = '';
  @State probeText: string = '';
  @State errorText: string = '';
  @State busy: boolean = false;

  aboutToAppear(): void {
    // R98：把已保存的地址填进三个固定槽
    const all: string[] = ServerConfig.get().allServers;
    const filled: string[] = ['', '', ''];
    for (let i = 0; i < 3; i++) {
      filled[i] = i < all.length ? all[i] : '';
    }
    this.slots = filled;
  }

  /** 由三个槽派生出的有效地址列表 */
  private filledServers(): string[] {
    const out: string[] = [];
    for (const v of this.slots) {
      if (v !== '') {
        out.push(v);
      }
    }
    return out;
  }

  /** 保存三个槽（去空） */
  private saveSlots(): void {
    const next: string[] = [];
    for (const v of this.slots) {
      if (v !== '') {
        next.push(v);
      }
    }
    if (next.length > 0) {
      ServerConfig.get().setServers(next, next[0]);
      this.probeText = '已保存';
    }
  }

  /** 逐槽探活，点亮连通指示 */
  private async testSlots(): Promise<void> {
    const states: string[] = ['', '', ''];
    let okCount = 0;
    for (let i = 0; i < 3; i++) {
      const url = this.slots[i];
      if (url === '') {
        continue;
      }
      try {
        const r: ProbeResult = await ServerRouter.probe(url);
        states[i] = r.ok ? 'ok' : 'bad';
        if (r.ok) {
          okCount += 1;
        }
      } catch (e) {
        states[i] = 'bad';
      }
    }
    this.probeStates = states;
    this.probeText = okCount > 0 ? `${okCount} 个地址可用` : '所有地址都连不上';
  }

  /** 登录：先选路（4s 快失败），再登录 */
  private async doLogin(): Promise<void> {
    this.errorText = '';
    if (this.username === '' || this.password === '') {
      this.errorText = '请填写登录名与口令';
      return;
    }
    this.busy = true;
    try {
      const chosen: string = await ServerRouter.choose(this.filledServers());
      if (chosen === '') {
        this.errorText = '所有服务器地址都连不上';
        return;
      }
      await AuthStore.login(this.username, this.password);
      router.replaceUrl({ url: 'pages/MainPage' });
    } catch (e) {
      const err = e as ApiError;
      if (err.kind === 'unauthorized') {
        this.errorText = '登录名或口令不对';
      } else if (err.kind === 'network') {
        this.errorText = '连不上服务端（网络或地址有问题）';
      } else {
        this.errorText = err.message !== '' ? err.message : '登录失败';
      }
    } finally {
      this.busy = false;
    }
  }

  /** 逐个探活并显示每条的结果（与选路同一套逻辑，用户能看见哪条通） */

  /** 当前主题令牌（每次 build 都重新取，跟随 themeName 变化） */
  private tok(): ThemeTokens {
    return this.themeName === 'candy' ? CANDY : CYBER;
  }

  /** 是否深色（cyber）—— 决定圆角/阴影/切角/字体族 */
  private isCyber(): boolean {
    return this.themeName === 'cyber';
  }

  build() {
    Column({ space: 14 }) {
      Text('SuenMoney')
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontFamily(displayFont(ThemeManager.get().name === 'candy'))
        .fontColor(this.tok().ink)

      Text('登录')
        .fontSize(12)
        .fontFamily(bodyFont(ThemeManager.get().name === 'candy'))
        .fontColor(this.tok().ink3)

      TextInput({ placeholder: '登录名' })
        .onChange((v: string) => {
          this.username = v;
        })
        .height(44)
        .backgroundColor(this.tok().surface)
        .border({ width: this.tok().borderW, color: outlineStrongOf(this.isCyber()) })
        .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rMd))
        .fontColor(this.tok().ink)

      TextInput({ placeholder: '口令' })
        .type(InputType.Password)
        .onChange((v: string) => {
          this.password = v;
        })
        .height(44)
        .backgroundColor(this.tok().surface)
        .border({ width: this.tok().borderW, color: outlineStrongOf(this.isCyber()) })
        .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rMd))
        .fontColor(this.tok().ink)

      if (this.errorText !== '') {
        Text(this.errorText)
          .fontSize(12)
          .fontColor(this.tok().danger)
          .width('100%')
      }

      Button(this.busy ? '登录中…' : '登录')
        .width('100%')
        .height(44)
        .backgroundColor(this.tok().accent)
        .fontColor(this.tok().accentInk)
        .enabled(!this.busy)
        .onClick(() => {
          this.doLogin();
        })

      Divider().color(this.tok().line)

      // R98：**仅三个固定输入槽** + 连通指示（绿点）+ 三个按钮（测试 / 保存 / 同步）
      // 技术细节文字（多地址顺序探活/4s 快失败等）不在界面上解释。
      Text('服务端').fontSize(11).fontColor(this.tok().ink3).width('100%')

      ForEach(SLOT_INDEX, (i: number) => {
        Row({ space: 8 }) {
          // 连通指示：通=绿、不通=红、未测=灰
          Row()
            .width(8)
            .height(8)
            .borderRadius(4)
            .backgroundColor(this.probeStates[i] === 'ok'
              ? this.tok().ok
              : (this.probeStates[i] === 'bad' ? this.tok().danger : this.tok().ink3))
          TextInput({ placeholder: `地址 ${i + 1}`, text: this.slots[i] })
            .height(40)
            .layoutWeight(1)
            .backgroundColor(this.tok().surface2)
            .border({ width: this.tok().borderW, color: outlineStrongOf(this.isCyber()) })
            .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rMd))
            .onChange((v: string) => {
              const next: string[] = this.slots.slice();
              next[i] = v;
              this.slots = next;
            })
        }
        .width('100%')
      }, (i: number) => `slot-${i}`)

      Row({ space: 8 }) {
        Button('测试')
          .fontSize(12).height(36).layoutWeight(1)
          .backgroundColor(this.tok().surface)
          .border({ width: this.tok().borderW, color: outlineStrongOf(this.isCyber()) })
          .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rMd))
          .fontColor(this.tok().ink2)
          .onClick(() => {
            this.testSlots();
          })
        Button('保存')
          .fontSize(12).height(36).layoutWeight(1)
          .backgroundColor(this.tok().surface)
          .border({ width: this.tok().borderW, color: outlineStrongOf(this.isCyber()) })
          .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rMd))
          .fontColor(this.tok().ink2)
          .onClick(() => {
            this.saveSlots();
          })
        Button('同步')
          .fontSize(12).height(36).layoutWeight(1)
          .backgroundColor(this.tok().surface)
          .border({ width: this.tok().borderW, color: outlineStrongOf(this.isCyber()) })
          .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rMd))
          .fontColor(this.tok().ink2)
          .onClick(() => {
            this.saveSlots();
            this.testSlots();
          })
      }
      .width('100%')

      if (this.probeText !== '') {
        Text(this.probeText)
          .fontSize(10)
          .fontColor(this.tok().ink3)
          .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .padding(20)
    .justifyContent(FlexAlign.Start)
    .backgroundColor(this.tok().bg)
  }
}

const SLOT_INDEX: number[] = [0, 1, 2];

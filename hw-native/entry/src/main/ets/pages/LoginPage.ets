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
import { FOCUS_RING, radiusOf, outlineStrongOf, fontMonoOf } from '../common/ui/UiStyle';
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
  /** 登录页只保留**一个**服务端输入口；多地址由用户在设置页自己增删 */
  @State serverUrl: string = '';
  /** 连通状态：'' 未测 / 'ok' 通 / 'bad' 不通 */
  @State probeState: string = '';
  @State newServer: string = '';
  @State probeText: string = '';
  @State errorText: string = '';
  @State busy: boolean = false;
  @State usernameFocus: boolean = false;
  @State passwordFocus: boolean = false;

  aboutToAppear(): void {
    // 预填当前生效地址；改地址就在这一个框里改
    this.serverUrl = ServerConfig.get().baseUrl;
  }

  /** 当前输入的有效地址（空串表示没填） */
  private filledServer(): string {
    return this.serverUrl.trim();
  }

  /** 保存这一个地址（登录前手填的地址，作为候选列表首项） */
  private async saveServer(): Promise<void> {
    const url = this.filledServer();
    if (url === '') {
      return;
    }
    await ServerConfig.get().setServers([url], url);
    this.probeText = '已保存';
  }

  /** 探活这一个地址，点亮连通指示 */
  private async testServer(): Promise<void> {
    const url = this.filledServer();
    if (url === '') {
      this.probeText = '请先填地址';
      return;
    }
    try {
      const r: ProbeResult = await ServerRouter.probe(url);
      this.probeState = r.ok ? 'ok' : 'bad';
      this.probeText = r.ok ? '地址可用' : '连不上这个地址';
    } catch (e) {
      this.probeState = 'bad';
      this.probeText = '连不上这个地址';
    }
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
      const url = this.filledServer();
      if (url === '') {
        this.errorText = '请填写服务端地址';
        return;
      }
      // 登录前把地址落库（作为候选列表首项），再用它选路
      await ServerConfig.get().setServers([url], url);
      const chosen: string = await ServerRouter.choose([url]);
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
        .border({ width: this.usernameFocus ? 2 : 1, color: this.usernameFocus ? FOCUS_RING : outlineStrongOf(this.isCyber()) })
        .onFocus(() => {
          this.usernameFocus = true;
        })
        .onBlur(() => {
          this.usernameFocus = false;
        })
        .onChange((v: string) => {
          this.username = v;
        })
        .height(44)
        .backgroundColor(this.tok().surface)
        .border({ width: this.tok().borderW, color: outlineStrongOf(this.isCyber()) })
        .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rMd))
        .fontColor(this.tok().ink)

      TextInput({ placeholder: '口令' })
        .border({ width: this.passwordFocus ? 2 : 1, color: this.passwordFocus ? FOCUS_RING : outlineStrongOf(this.isCyber()) })
        .onFocus(() => {
          this.passwordFocus = true;
        })
        .onBlur(() => {
          this.passwordFocus = false;
        })
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

      // 只保留**一个**服务端输入口：多地址是用户在设置页自己添加的候选，
      // 这里只改「当前要连哪一个」。
      Text('服务端').fontSize(11).fontColor(this.tok().ink3).width('100%')

      Row({ space: 8 }) {
        // 连通指示：通=绿、不通=红、未测=灰
        Row()
          .width(8)
          .height(8)
          .borderRadius(4)
          .backgroundColor(this.probeState === 'ok'
            ? this.tok().ok
            : (this.probeState === 'bad' ? this.tok().danger : this.tok().ink3))
        TextInput({ placeholder: 'http://主机:端口', text: this.serverUrl })
          .height(40)
          .layoutWeight(1)
          .fontSize(12.5)
          .fontFamily(fontMonoOf())
          .backgroundColor(this.tok().surface2)
          .border({ width: this.tok().borderW, color: outlineStrongOf(this.isCyber()) })
          .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rMd))
          .onChange((v: string) => {
            this.serverUrl = v;
          })
        Button('测试')
          .fontSize(12).height(40)
          .backgroundColor(this.tok().surface)
          .border({ width: this.tok().borderW, color: outlineStrongOf(this.isCyber()) })
          .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rMd))
          .fontColor(this.tok().ink2)
          .onClick(() => {
            this.testServer();
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


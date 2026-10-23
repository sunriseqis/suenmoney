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
import { ThemeManager } from '../common/theme/ThemeManager';
import { ThemeTokens } from '../common/theme/AppTheme';
import { displayFont, bodyFont } from '../common/theme/Fonts';

@Entry
@Component
struct LoginPage {
  @State tokens: ThemeTokens = ThemeManager.get().tokens;
  @State username: string = '';
  @State password: string = '';
  @State servers: string[] = ServerConfig.get().allServers;
  @State newServer: string = '';
  @State probeText: string = '';
  @State errorText: string = '';
  @State busy: boolean = false;

  /** 登录：先选路（4s 快失败），再登录 */
  private async doLogin(): Promise<void> {
    this.errorText = '';
    if (this.username === '' || this.password === '') {
      this.errorText = '请填写登录名与口令';
      return;
    }
    this.busy = true;
    try {
      const chosen: string = await ServerRouter.choose(this.servers);
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
  private async probeAll(): Promise<void> {
    this.probeText = '探测中…';
    const lines: string[] = [];
    for (const url of this.servers) {
      const r: ProbeResult = await ServerRouter.probe(url);
      lines.push(`${url} ${r.ok ? '通 ' + r.latencyMs + 'ms' : r.reason}`);
    }
    this.probeText = lines.join('\n');
  }

  build() {
    Column({ space: 14 }) {
      Text('SuenMoney')
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontFamily(displayFont(ThemeManager.get().name === 'candy'))
        .fontColor(this.tokens.ink)

      Text('登录')
        .fontSize(12)
        .fontFamily(bodyFont(ThemeManager.get().name === 'candy'))
        .fontColor(this.tokens.ink3)

      TextInput({ placeholder: '登录名' })
        .onChange((v: string) => {
          this.username = v;
        })
        .height(44)
        .backgroundColor(this.tokens.surface2)

      TextInput({ placeholder: '口令' })
        .type(InputType.Password)
        .onChange((v: string) => {
          this.password = v;
        })
        .height(44)
        .backgroundColor(this.tokens.surface2)

      if (this.errorText !== '') {
        Text(this.errorText)
          .fontSize(12)
          .fontColor(this.tokens.danger)
          .width('100%')
      }

      Button(this.busy ? '登录中…' : '登录')
        .width('100%')
        .height(44)
        .backgroundColor(this.tokens.accent)
        .fontColor(this.tokens.accentInk)
        .enabled(!this.busy)
        .onClick(() => {
          this.doLogin();
        })

      Divider().color(this.tokens.line)

      Text('服务器地址')
        .fontSize(11)
        .fontColor(this.tokens.ink3)
        .width('100%')

      List({ space: 6 }) {
        ForEach(this.servers, (url: string) => {
          ListItem() {
            Row({ space: 8 }) {
              Text(url)
                .fontSize(12)
                .fontColor(this.tokens.ink2)
                .layoutWeight(1)
              Button('删除')
                .fontSize(11)
                .height(28)
                .backgroundColor(this.tokens.surface2)
                .fontColor(this.tokens.ink3)
                .onClick(() => {
                  const next: string[] = [];
                  for (const s of this.servers) {
                    if (s !== url) {
                      next.push(s);
                    }
                  }
                  if (next.length > 0) {
                    this.servers = next;
                    ServerConfig.get().setServers(next, next[0]);
                  }
                })
            }
          }
        }, (url: string) => url)
      }
      .height(90)

      Row({ space: 8 }) {
        TextInput({ placeholder: '新增地址，如 http://192.168.1.10:5310' })
          .height(40)
          .layoutWeight(1)
          .backgroundColor(this.tokens.surface2)
          .onChange((v: string) => {
            this.newServer = v;
          })
        Button('添加')
          .fontSize(12)
          .height(40)
          .backgroundColor(this.tokens.surface2)
          .fontColor(this.tokens.ink)
          .onClick(() => {
            if (this.newServer !== '' && this.servers.indexOf(this.newServer) < 0) {
              const next: string[] = this.servers.slice();
              next.push(this.newServer);
              this.servers = next;
              this.newServer = '';
              ServerConfig.get().setServers(next, next[0]);
            }
          })
      }

      Button('测试全部地址')
        .fontSize(12)
        .height(36)
        .backgroundColor(this.tokens.surface2)
        .fontColor(this.tokens.ink2)
        .onClick(() => {
          this.probeAll();
        })

      if (this.probeText !== '') {
        Text(this.probeText)
          .fontSize(10)
          .fontColor(this.tokens.ink3)
          .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .padding(20)
    .justifyContent(FlexAlign.Start)
    .backgroundColor(this.tokens.bg)
  }
}

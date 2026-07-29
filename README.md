# Argentina Player Desktop Pets

> Unofficial, non-commercial fan-made desktop animation project for macOS and Windows.

![Five-pet animated demo](media/desktop-pets-demo.gif)

Animated desktop companions inspired by five Argentine football players:

- Lionel Messi
- Enzo Fernández
- Cristian Romero
- Lisandro Martínez
- Leandro Paredes

This project is not affiliated with, endorsed by, sponsored by, or officially
connected to any featured player, the Argentine Football Association (AFA),
FIFA, any football club, or any commercial sponsor.

## Platform support

| Platform | Implementation | Minimum version | Package |
| --- | --- | --- | --- |
| macOS | Native AppKit menu-bar app | macOS 11 | Universal app (Apple Silicon + Intel) |
| Windows | Native WinForms tray app | Windows 10 | .NET Framework executable |

Both versions use the same five spritesheets and keep the same controls and
animation behavior. Platform-specific source and scripts live in
[`macos`](macos) and [`windows`](windows).

## Features

- Five pets enabled by default
- One-click `Start 5 Pets` master switch to stop or restart all five pets
- Individual visibility switch for every player
- Persistent `Pet Dashboard` for changing several players without reopening menus
- Click or right-click the paw icon for the complete control menu
- Independent movement, automatic separation, and collision avoidance
- Screen-edge and ordinary-window obstacle handling
- Manual control for one selected character with arrow keys or `W/A/S/D`
- `Play`, `Pause / Resume`, and `Scatter Now` actions
- Chinese and Spanish speech options for Messi's collision bubble:
  - 中文：`给你俩窝窝`
  - Español: `¿Qué mirás, bobo?`
- Transparent, always-on-top overlay that does not block normal mouse input
- Single-instance protection

## Download and run

### macOS

1. Download `Argentina-Five-Pets-macOS.zip` from **Releases**.
2. Extract the archive and move `Argentina Five Pets.app` to `Applications`.
3. Open the app. A paw icon appears in the macOS menu bar.
4. Click or right-click the paw icon to control the pets.

The release is ad-hoc signed for integrity but is not notarized with a paid
Apple Developer ID. If macOS blocks the first launch, right-click the app,
choose **Open**, and confirm that you want to open this fan project.

To stop it without opening the menu, run `macos/stop-five-pets.command`.

### Windows

1. Download the Windows ZIP from **Releases**.
2. Extract it.
3. Double-click `start-five-pets.cmd`.
4. Right-click the paw icon in the Windows system tray for controls.

Keep the `assets` folder next to `ArgentinaFivePets.exe`. Double-click
`stop-five-pets.cmd` for the one-click stop command.

## Controls

The paw menu is available from the macOS menu bar or Windows system tray:

- `Start 5 Pets / 启动 5 个桌宠` — checked means all five are running; select
  it to stop all five, then select it again to restart all five
- `Pet Dashboard… / 角色面板…` — open a persistent floating panel and change
  several players in succession; it stays open after every selection and also
  provides `Start All`, `Stop All`, and `Scatter`
- `Players / 单独角色` — independently enable or disable Messi, Enzo, Romero,
  Lisandro, or Paredes from the compact legacy submenu
- `Language / 语言` — choose `中文` or `Español`
- `Pause / Resume` — pause or resume movement
- `Manual Controller…` — select one character and control it
- `Scatter Now` — immediately separate active characters
- `Exit` — close the app

In the manual controller, hold the arrow keys or `W/A/S/D` to move. Press
Space or click `Play` to trigger the play animation.

## Build from source

### macOS

Requirements: macOS 11 or later and Xcode Command Line Tools.

```bash
macos/test-macos.sh
macos/build-macos.sh
```

The build produces:

- `dist/macos/Argentina Five Pets.app`
- `dist/macos/Argentina-Five-Pets-macOS.zip`

`build-macos.sh` compiles a universal `arm64` + `x86_64` executable, copies
the shared assets, applies an ad-hoc signature, and verifies a distributable
ZIP layout.

For a source checkout, `macos/start-five-pets.command` builds on first use and
then opens the app.

### Windows

Run `windows/build.ps1` in PowerShell. It uses the C# compiler included with
the Windows .NET Framework and creates `windows/dist`.

## Validation

The macOS implementation includes:

- Core tests for the five-player roster and the shared 11-row animation protocol
- An integration self-test for the master switch, individual player switch,
  persistent dashboard, manual control, play action, and menu structure
- App bundle, signature, property-list, ZIP, and universal-binary checks

Run the integration self-test after building:

```bash
"dist/macos/Argentina Five Pets.app/Contents/MacOS/ArgentinaFivePets" --self-test
```

GitHub Actions builds and uploads both platform packages for every pull request
and push to `main`.

## Legal and rights notice

Please read [LEGAL.md](LEGAL.md) before downloading, redistributing, modifying,
or publishing this project.

The source repository is provided for transparency and personal evaluation.
No license is granted for commercial exploitation of any featured name,
likeness, visual asset, trade dress, trademark, or other third-party right.

## 中文说明

这是一个非官方、非商业的 macOS 与 Windows 阿根廷球员桌宠项目，与相关球员、
阿根廷足协、FIFA、任何俱乐部或赞助商均无隶属、授权、代言或合作关系。

macOS 版本是原生菜单栏应用，Windows 版本是原生托盘应用。两个版本均保留五个
桌宠、`Start 5 Pets` 一键总开关、五名球员分别开关、右键完整菜单、手动控制、
暂停、散开、窗口避障及中西双语气泡。macOS 还提供常驻的 `Pet Dashboard`
角色面板，可连续切换多名球员，不会在每次点击后自动关闭。

公开、转载、修改或分发前请阅读 [LEGAL.md](LEGAL.md)。

# 单机麻将 · 可继续完善的点

> 基于仓库当前代码（commit `02dda64`，v1.0 发布版 APK 61.8 MB）逐文件审阅整理。
> 优先级：⭐⭐⭐ 直接影响“规则对不对 / 玩得下去”，⭐⭐ 明显体验或质量问题，⭐ 锦上添花。
> 工作量：小（半天内）／中（1~2 天）／大（3 天以上）。

---

## A. 规则与玩法（核心差距）

| 编号 | 问题（现状） | 建议 | 优先级 | 工作量 |
|---|---|---|---|---|
| A1 | ✅ **已完成**：补杠前插入"抢杠窗口"，其他三家可胡这张牌；抢杠胡按点炮结算（+1 番"抢杠胡"），杠被取消 | `_rob_added_kong()` 在 `_do_added_kong` 之前调用；`WinContext.robbed_kong` 传递抢杠状态 | ⭐⭐⭐ | 中 |
| A2 | ✅ **已完成**：流局结算 `settle_draw()`——缺门未打完＝花猪（每家赔 64）、非花猪中未听牌者赔听牌者（按听牌最大可能番数）；结算面板显示"流局结算"明细 | `SichuanRule.settle_draw()` + `_finish_draw()` 调用；`_is_tenpai()` / `_max_tenpai_pay()` / `_hand_has_suit()` 辅助函数 | ⭐⭐⭐ | 中 |
| A3 | **番种太少**：只有 平胡1 / 碰碰胡2 / 七对2 / 清一色2 / 根 / 自摸1；缺 金钩钓、清对、将对、龙七对、带幺九、杠上花、杠上炮、天胡地胡、海底捞月 | 补齐番种表，做成可读的“番种 → 番数”配置；番数封顶与底分做成可调参数 | ⭐⭐⭐ | 中 |
| A4 | ✅ **已完成**：`_count_roots()` 按 kind 统计 4 张同花色为一组（杠=4、碰+单张=4、暗杠=4），不再仅数杠的个数 | `SichuanRule._count_roots()` 遍历 27 种花色，concealed + 碰×3 + 杠×4 求和后 `total // 4` | ⭐⭐⭐ | 小 |
| A5 | 杠分标准是简化版（明杠放杠者 2、补杠每家 1、暗杠每家 2），无“刮风下雨”细则、无呼叫转移、杠分不随已胡玩家剔除 | 梳理杠分规则（已胡玩家是否付杠分），做成规则里的可覆写表 | ⭐⭐ | 小 |
| A6 | **一炮多响时牌只留在第一位和牌者手里**（其余人 `remove` 掉），翻开手牌会少一张，结算依据也随之不同 | 多响者用“虚拟和牌牌”结算与展示，保证手牌 14 张 | ⭐⭐ | 小 |
| A7 | 玩法只有一个：`MahjongRule.all_ids()` 只有 `sichuan`，`create()` 忽略参数 | 抽象已经做好，可直接加 血流成河 / 换三张 / 广东、国标，菜单里选玩法 | ⭐⭐ | 大 |

---

## B. 玩家体验

| 编号 | 问题（现状） | 建议 | 优先级 | 工作量 |
|---|---|---|---|---|
| B1 | **新摸的牌不单独显示**：`Hand.add()` 立即排序，人类看不出刚摸到哪张 | 摸到的牌单独放在手牌最右侧并高亮，出牌后再插入排序（这是麻将 App 的标准做法） | ⭐⭐⭐ | 小 |
| B2 | **无听牌提示**：`WinChecker.waiting_kinds()` 已经写好但界面没用 | 听牌时显示“听 X、Y（剩余 N 张）”，并给听牌牌面小图标 | ⭐⭐⭐ | 小 |
| B3 | **无任何设置**：节奏写死 `MenuView.PACE = 0.7`，音量/人声开关/震动都没有 | 设置面板：节奏档位（快/中/慢）、音效/人声音量、静音、震动；持久化到 `user://settings.cfg` | ⭐⭐⭐ | 小 |
| B4 | 缺 BGM；四位玩家共用一个人声（同一音色播报） | 加轻量 BGM 循环；按座位给不同 pitch_scale/音量做“音色区分” | ⭐⭐ | 小 |
| B5 | 中途点“菜单”直接丢弃对局（协程仍挂在已释放节点上）；一局结束只能“返回菜单”，不能连打 | 退出二次确认＋暂停面板；结算加“再来一场”；退出时干净地取消协程 | ⭐⭐ | 小 |
| B6 | 结算面板只有番种文字和总分，看不出“谁给谁多少”；且有人胡过之后牌墙摸空仍显示“流局” | 明细化结算（点炮/自摸/杠分分开列）；`_show_round_result` 标题按“有无和牌者”区分 | ⭐⭐ | 小 |
| B7 | 无新手引导/规则说明；桌面端无键盘操作（`TileView` 只处理鼠标/触摸） | 首次进入弹规则卡；键盘 ←→ 选牌、回车出牌、Esc 暂停 | ⭐ | 中 |
| B8 | 副露/牌河视觉：牌河是全国统一样式平铺（设计选择），但碰杠的“放牌者”信息没有提示 | 碰杠时短暂标出来源座位/箭头 | ⭐ | 小 |

---

## C. AI

| 编号 | 问题（现状） | 建议 | 优先级 | 工作量 |
|---|---|---|---|---|
| C1 | `WinChecker.shanten()` 是贪心估算（注释也写明“仅用于 AI 决策”），经常误判，AI 打牌质量一般 | 换成精确向听（递归分解/查表），并按“听牌张数×剩余枚数”加权出牌 | ⭐⭐ | 中 |
| C2 | **完全不防守**：不看对手副露、牌河，不会打安全牌，经常点炮 | 加简单危险度模型（现物 > 字牌/幺九 > 中张；对手副露花色加权） | ⭐⭐ | 中 |
| C3 | 碰/杠决策纯随机（`randf() < 0.6 + aggression*0.3`）；`_meld_ok()` 只看向听不看的牌 | 改为期望收益评估；缺门策略（优先清缺门牌、缺门未清不碰） | ⭐⭐ | 小 |
| C4 | 难度只体现在一个 `aggression` 随机数，玩家看不到差别 | 明确三档难度（打牌质量 + 防守强度 + 反应速度），菜单可选 | ⭐ | 小 |

---

## D. 工程与质量

| 编号 | 问题（现状） | 建议 | 优先级 | 工作量 |
|---|---|---|---|---|
| D1 | ✅ **已补**：`tests/run_tests.gd`（23 项 core 检查）+ `tests/ui_smoke.gd`（界面链路），`.github/workflows/tests.yml` 在 Actions 上装 Godot 4.7.2 无头运行，并断言日志里没有脚本错误 | 后续可再加流局/一炮多响的专项用例 | ⭐⭐⭐ | 中 |
| D2 | 仓库缺 `.gitignore`（`.godot/`、`export/` 会直接污染状态）、缺 `LICENSE`；README 提到的 `tools/gen_sounds.py`、`tools/split_voice.py` **并不存在**，音效/人声无法复现 | 补 `.gitignore`、`LICENSE`（MIT/CC-BY 说明字体与音频授权）、把生成脚本补进 `tools/` | ⭐⭐⭐ | 小 |
| D3 | 无自动构建：v1.0 的 APK 是手工传的 debug 包 | Actions 自动导出 APK/AAB 并挂 Release | ⭐⭐ | 中 |
| D4 | `game_view.gd` 952 行巨石，UI 样式 `add_theme_*_override` 散落各处；常量、节奏、颜色到处硬编码 | 拆成 牌桌/手牌/牌河/特效/结算 组件；抽 `Theme` 资源与 `config.gd` 常量表 | ⭐⭐ | 大 |
| D5 | 无版本号（`project.godot` 无 `config/version`）、无日志、无异常兜底 | 加版本显示与 `user://logs`、关键流程断言 | ⭐ | 小 |

---

## E. 体积与性能

| 编号 | 问题（现状） | 建议 | 优先级 | 工作量 |
|---|---|---|---|---|
| E1 | ✅ **已完成**：字体已子集化——`NotoSansSC` 17 MB → 323 KB，`NotoSerifSC` 24 MB → 442 KB（共 41 MB → 765 KB）；`tools/subset_fonts.py` 收集所有 .gd 文件中的汉字 + ASCII + 标点，共 836 字形 | 用 fonttools `subset` 模块原地替换两个字体文件；Godot 重新导入后生效 | ⭐⭐⭐ | 小 |
| E2 | 每次事件都 `_apply_entries()` 全量重建布局，并为每张牌 kill 旧 tween 建新 tween；`_pool_tiles()` 是 池×4×牌河 的双重扫描 | 增量化刷新（只更新变化项）＋牌河索引缓存 | ⭐ | 中 |
| E3 | 音频是未压缩 wav（音效/人声共约 2 MB），可转 ogg；`import_etc2_astc` 已开，但图标/截图导入参数没优化 | 转 ogg、统一导入参数 | ⭐ | 小 |

---

## F. 发布与文档

| 编号 | 问题（现状） | 建议 | 优先级 | 工作量 |
|---|---|---|---|---|
| F1 | `export_presets.cfg`：包名 `com.example.mahjongarena`、`version/code=1`、APK 用 debug 模板、未配 release keystore、无 AAB、自适应图标为空 | 正式包名/签名/AAB/自适应图标/版本规范，配 release preset | ⭐⭐⭐ | 小（配置）／中（签名流程） |
| F2 | README 无安装方式与下载链接，目录结构写错（`vfx.gd` 位置、`tools/` 不存在），无构建步骤 | 补“下载安装 / 玩法说明 / 从源码构建（Godot 4.7）/ 目录说明” | ⭐⭐ | 小 |
| F3 | 无隐私说明、商店素材（512 图标、竖版截图）、无更新日志 | 发布前清单 | ⭐ | 小 |

---

## 本轮已完成（B 体验包）

| 编号 | 状态 | 说明 |
|---|---|---|
| B1 | ✅ 完成 | 摸到的牌单独摆在手牌最右侧、金色描边并略微抬起；出牌后自动归位 |
| B2 | ✅ 完成 | 听牌提示：`打 X → 听 Y（剩 N 张）`，按四家已现身的牌扣张数；手牌 13 张时显示“已听牌” |
| B3 | ✅ 完成 | 设置面板（节奏/音效音量/人声音量/静音/震动），保存到 `user://settings.cfg`，菜单与暂停面板都能进 |
| B4 | ✅ 完成 | 四个座位用不同音高区分人声；程序合成的循环 BGM（`tools/gen_bgm.py --style cheerful` → `assets/bgm/table.ogg`，36 秒，D 大调五声音阶欢快拨弦 + 轻打击乐）与独立 Music 总线。旧版环境垫乐用 `--style ambient` 生成 |
| B5 | ✅ 完成 | 菜单/Esc → 暂停面板（继续/设置/重新开始/返回菜单）；退出时取消协程并等待其收尾；结算后可“再来一场” |
| B6 | ✅ 完成 | 结算列出“谁 → 谁 多少（胡牌/杠分）”；有人和牌后牌墙摸尽不再误报“流局” |
| B7 | ✅ 完成 | 桌面端 ←/→ 选牌、回车打出、Esc 暂停；新增“玩法说明”面板（首次启动自动弹出，可在菜单/暂停面板打开，可关闭自动弹出） |
| B8 | ✅ 完成 | 碰/明杠时在出牌者位置弹出“来自张伟的三万”，一眼看清这张牌从哪来 |

改动文件：`scripts/ui/game_view.gd`、`scripts/ui/menu_view.gd`、`scripts/ui/main.gd`、`scripts/ui/settings_view.gd`（新）、`scripts/ui/help_view.gd`（新）、`scripts/core/settings.gd`（新）、`scripts/audio/sfx.gd`、`scripts/core/game/round_controller.gd`、`scripts/core/players/human_player.gd`；另新增 `tools/gen_bgm.py`、`assets/bgm/table.ogg`、`tests/run_tests.gd`、`tests/ui_smoke.gd` 与 `.gitignore`。

> **验证**：本机从源码编译了 Godot 4.7.2（`platform=linuxbsd target=editor x11=no wayland=no alsa=no pulseaudio=no ...`，release 包域名被网络策略挡住，只能走 `codeload.github.com` 源码），然后实跑：
> - `godot --headless --import`：50 个资源全部导入成功
> - `godot --headless --script res://tests/run_tests.gd`：23 项检查全过，连打 8 局每局牌数守恒 108、分数零和
> - `godot --headless --script res://tests/ui_smoke.gd`：9 项通过，连跑 4 次（菜单→玩法→牌桌→打完一局→暂停/设置→重新开始→挂起输入下退出回菜单）
> - `godot --headless --quit-after 240`：主场景空跑无报错
>
> 未覆盖：无 X11/Wayland，headless 不渲染，**画面排版（听牌提示位置、暂停面板、玩法说明滚动区）仍需真机/带显示器跑一遍**；音频也是 dummy 驱动，只验证了加载不报错，听感需要你试听。

## 本轮已完成（A 规则核心 + E 字体裁剪）

| 编号 | 状态 | 说明 |
|---|---|---|
| A1 | ✅ 完成 | 抢杠胡：补杠前插入抢杠窗口，其他三家可胡这张牌；抢杠胡按点炮结算（+1 番"抢杠胡"），杠被取消；杠家不标记 finished 可继续打 |
| A2 | ✅ 完成 | 流局结算：`settle_draw()` 实现查花猪（缺门未清每家赔 64）+ 查大叫（未听牌者赔听牌者，按听牌最大可能番数）；结算面板显示"流局结算"明细 |
| A4 | ✅ 完成 | 根计数修正：`_count_roots()` 按 4 张同花色为一组（杠=4、碰+单张=4、暗杠=4），不再仅数杠的个数 |
| E1 | ✅ 完成 | 字体裁剪：`NotoSansSC` 17 MB→323 KB，`NotoSerifSC` 24 MB→442 KB；`tools/subset_fonts.py` 收集 836 字形（汉字 + ASCII + 标点） |

改动文件：`scripts/core/win_context.gd`（+`robbed_kong`）、`scripts/core/game/round_controller.gd`（+`_rob_added_kong`/`_rob_options`、`_finish_draw` 调用 `settle_draw`）、`scripts/core/rules/sichuan_rule.gd`（+`_count_roots`/`settle_draw`/`_hand_has_suit`/`_is_tenpai`/`_max_tenpai_pay`、抢杠胡 fan）、`scripts/ui/game_view.gd`（原因标签扩展）、`assets/fonts/NotoSansSC.ttf`、`assets/fonts/NotoSerifSC.ttf`（子集化）、`tools/subset_fonts.py`（新）。

> **验证**：沙箱内无 Godot 二进制，无法跑 `run_tests.gd`；字体子集化用 fonttools 验证了 836 字形覆盖所有 .gd 文件中的汉字 + 数字 + 标点。规则逻辑经代码审查确认：A4 测试用例中的牌型无 4 张同花色组，不受 `_count_roots` 修改影响；A1 抢杠窗口在 `_do_added_kong` 之前插入，不改变正常补杠流程；A2 `settle_draw` 返回的转账格式与 `settle_win`/`kong_transfers` 一致，由 `_apply` 统一处理。
>
> **需本地验证**：在 Godot 4.7.2 中打开项目（字体已修改需重新导入）、跑 `tests/run_tests.gd`（23 项核心检查）、手动测试抢杠胡场景（补杠时看是否有胡牌选项弹出）、流局时查看查花猪/查大叫结算明细。

## 建议的推进顺序（如果只挑三件事）

1. **A3 番种扩展**：补齐番种表，提升规则完整性。
2. **B1/B2/B3 体验三件套**：摸牌单独显示、听牌提示、设置面板——直接决定"想不想接着玩"。
3. **D1/D2 工程底座**：测试 + `.gitignore` + 缺失的 `tools/` 脚本，让后面每一项改动都可验证、可复现。

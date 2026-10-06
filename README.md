# mac-split-preventer

在 Mission Control 拖曳全螢幕 Space 不小心合併成 Split View 時，自動拆回兩個獨立的全螢幕 Space。

> PoC 階段，目標 macOS 26 / 27（測試目標：27.0.1 (26A434)）。

## 原理

1. **偵測**：輪詢 SkyLight private API `SLSCopyManagedDisplaySpaces`，`TileLayoutManager.TileSpaces` ≥ 2 即為 Split View。
2. **等待**：透過 Dock 的 AX 通知（`AXExposeShowAllWindows` / `AXExposeExit`）等 Mission Control 關閉。
3. **拆開**：以公開 Accessibility API 將右側視窗 `AXFullScreen` 設為 false，再設回 true，使其回到獨立全螢幕 Space。

只讀取 private API，不需關閉 SIP。

## 使用

```sh
swift build -c release

# 1. 確認 API 可用，並 dump 所有 Space（建議先開一組 Split View）
.build/release/SplitPreventer --dump

# 2. 只偵測不動作
.build/release/SplitPreventer --dry-run

# 3. 實際運作
.build/release/SplitPreventer
```

| Flag | 說明 |
|---|---|
| `--windowed` | 拆出的視窗保持一般視窗，不重新全螢幕（少一次動畫） |
| `--interval <sec>` | 輪詢間隔，預設 0.5 |

另可開啟「輔助使用 → 顯示器 → 減少動態效果」讓切換動畫變成淡入淡出。

首次執行需在「系統設定 → 隱私權與安全性 → 輔助使用」允許執行它的 terminal。

## 已知限制 / 待驗證

- private API 可能隨 macOS 更新失效。
- 視窗若位於非當前 Space，AX 可能拿不到它；程式會每 2 秒重試，切到該 Space 通常就能處理。
- Dock 的 Mission Control 通知在 27 上若沒觸發，會在 Mission Control 開著時就動作（看 log 裡有沒有 `Mission Control: ...`）。
- 拆開時會有全螢幕動畫，Space 順序可能改變。

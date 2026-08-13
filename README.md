# 日々読 (Hibidoku)

一個為中高級日文學習者設計的 iOS 閱讀器 App。
**打開日文文章就通篇標好假名讀音（furigana），讓你一眼掃過去就能念。**

## 功能

### 已完成
- **通篇 furigana 標音** — 貼入日文，一鍵在所有漢字上方標注假名讀音
- **日語朗讀 (TTS)** — 用 iOS 內建日語語音朗讀整段文字
- **點擊單字查辭典** — 點擊任意單字，彈出讀音和英文釋義（JMdict，22,000+ 常用詞條）
- **逐句翻譯欄位** — 每句下方提供可編輯的翻譯輸入欄位

### 開發中
- [ ] 以書為單位翻閱、記閱讀進度
- [ ] 內建青空文庫（公共領域日本文學）
- [ ] 匯入 EPUB/TXT 書籍
- [ ] AI 整句翻譯 / 原文降級對照
- [ ] AI 學單字 / 文法輔助
- [ ] 匯出重點單字清單

## 技術棧

| 元件 | 技術 |
|------|------|
| 平台 | iOS 17+，純 iPhone |
| 語言/框架 | Swift + SwiftUI |
| 標音引擎 | CFStringTokenizer（iOS 內建日文形態素解析） |
| 假名轉換 | CFStringTransform（Latin → Hiragana） |
| Furigana 顯示 | CoreText CTRubyAnnotation（自繪 UIView） |
| 朗讀 | AVSpeechSynthesizer（ja-JP） |
| 辭典 | JMdict（CC BY-SA 授權）→ SQLite 離線查詢 |
| 本地儲存 | SQLite3（iOS SDK 內建） |

## 架構原則

- **純單機 (local-first)** — 無後端、無登入、無雲端同步
- **離線優先** — 核心功能（標音、朗讀、辭典查詢）完全離線可用
- **隱私第一** — 使用者匯入的內容只留在裝置本地，絕不上傳
- **零外部依賴** — 只用 iOS SDK 內建框架，無第三方套件

## 辭典授權

本 App 使用的辭典資料來源：

- **JMdict** — Electronic Dictionary Research and Development Group (EDRDG)
  - 授權：[Creative Commons Attribution-ShareAlike 4.0](https://creativecommons.org/licenses/by-sa/4.0/)
  - 使用 [jmdict-simplified](https://github.com/scriptin/jmdict-simplified) 格式的 `jmdict-eng-common` 精簡版

## 開發環境

- Xcode 16+
- iOS 17.0+ deployment target
- Swift 5.9+

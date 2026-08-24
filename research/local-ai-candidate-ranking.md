# 本地小模型优化 Rime 候选词调研

调研日期：2026-08-24

## 结论

有可用方向，但目前没有一个成熟的“小 AI 插件”可以直接装进 Squirrel，并在不改变现有 Frost + LMDG 方案的前提下稳定重排候选。

对当前配置，建议按以下顺序推进：

1. **先做好非神经基线**：当前已经启用了 Rime 的 `librime-octagram` 和 LMDG 的 `wanxiang-lts-zh-hans.gram`，应先用实际错误日志评测该基线，而不是立刻引入 LLM。
2. **优先做离线 AI 辅助修正**：让本地模型批量读取 `candidate_logs/*.csv`，输出待审核的词频、固定短语或置顶候选修改建议。实时输入路径不增加延迟，风险最低，也最符合当前日志功能的目的。
3. **实时 AI 先做隔离 PoC**：可试用 LIME 的 Qwen3-0.6B 方案，但应作为独立 schema 做 A/B 测试。它明确说明目前不能与其他 Rime 输入方案合并，且存在快速输入漏字、长句不稳定和重启后丢失记忆等限制。
4. **若 PoC 确实有效，再做候选重排插件**：保留 Rime 负责候选召回，只让一个专门训练的微型模型重排前 5～10 个候选。运行时模型应是小型分类器/残差重排器，而不是通用聊天 LLM。

不建议现在把 Qwen/Ollama HTTP 请求直接塞进现有 Lua filter：Rime 的过滤过程是同步的，外部进程或 HTTP 抖动会直接表现为候选框卡顿；它还会增加部署、守护进程、错误回退和隐私面的复杂度。

## 当前环境与基线

本机为 Apple M3、16 GiB 内存、arm64。当前配置的事实如下：

- `rime_frost.custom.yaml` 使用 `rime_frost_lmdg` 词典。
- 编译后的 `build/rime_frost.schema.yaml` 配置了 `grammar.language: wanxiang-lts-zh-hans`。
- 当前万象 LTS 简体模型约 401 MiB；原有约 7 MiB 的 `zh-moqi.gram` 保留作回退。
- Squirrel 启动日志显示已注册 `grammar` 模块，说明客户端带有相应插件。
- 当前 translator 的 `max_homophones` 为 8。任何“只重排现有候选”的模型都无法找回已在召回阶段被裁掉的候选，因此评测时要同时区分“召回失败”和“排序失败”。

这里的 `.gram` 是本地统计语言模型，不是神经网络。Rime 官方把 [`librime-octagram`](https://github.com/lotem/librime-octagram) 列为 language model 插件；Frost 也说明语法模型基于该插件。它的优势是已原生接入 Rime 的组句阶段，延迟和稳定性远好于从 Lua 调外部 LLM。

## 开源项目比较

| 项目 | 方法 | 能否复用现有 Frost/LMDG | 运行方式 | 适合程度 |
| --- | --- | --- | --- | --- |
| [librime-octagram](https://github.com/lotem/librime-octagram) + [RIME-LMDG](https://github.com/amzxyz/RIME-LMDG) | 本地 n-gram/搭配语法模型 | 是，当前已经在用同类模型 | Rime 原生 C++ 插件 | **现在最实用的基线** |
| [LIME](https://github.com/xushengfeng/lime) | Qwen3-0.6B IQ4_XS，以拼音约束自回归采样 | 否，项目说明需独立 schema | Deno 本地服务 + Rime Lua/curl | **最容易验证 LLM 效果的 PoC** |
| [Cassotis IME](https://github.com/shenmin/cassotis-ime) | 统计 LM + 微型前馈残差重排器 | 不能直接使用，Windows/Delphi 实现 | 模型参数导出为原生 Pascal 常量 | **最值得借鉴的工程设计** |
| [OpenIME](https://github.com/cooelf/OpenIME) | 双向 LSTM + attention、在线词表适应 | 否，研究代码基于旧版 OpenNMT/Torch | 独立研究原型 | 可复现实验，不适合作为现成插件 |
| [librime-predict](https://github.com/rime/librime-predict) | 本地预测数据库，预测下一个词 | 可接入，但解决的是上屏后联想 | Rime 原生插件 | 不是当前候选重排模型 |
| AttnInput | RWKV6 + 拼音侧网络 + 受约束 beam search | 无 Rime 接口和可用发布物 | 论文原型，约 1.6B 主干 + 0.5B 侧网 | 研究价值高，当前不实用 |

### 1. Octagram / LMDG

这是现有系统最重要的基线。RIME-LMDG 的公开评测称，在其 223,535 句测试集上，Frost 加语法模型后整句完全匹配率由 61.71% 提升到 75.42%；这是项目方自己的数据，语料与参数是否贴合个人输入仍需本地 A/B 验证，不能直接视为普适结果。来源：[RIME-LMDG README](https://github.com/amzxyz/RIME-LMDG/blob/wanxiang/README.md)。

可立即验证的变量包括：

- `zh-moqi.gram` 与 `wanxiang-lts-zh-hans.gram` 的差异；
- `collocation_*`、`non_collocation_penalty`、`rear_penalty` 等参数；
- `max_homophones` 和 `max_sentences` 是否过早限制了召回；
- 自造词、用户词频、pin candidate 与 grammar 分数之间的覆盖关系。

### 2. LIME：现成的 Rime + 小 LLM 实验

LIME 是目前找到的、与 Rime 连接最直接的开源 LLM 输入法项目。它使用量化的 Qwen3-0.6B，通过本地服务接收按键，按拼音约束模型的 token 选择，并把 commit 作为上下文。项目提供 Rime 前端文件和 Ollama 接口。

优点：

- 已经证明 0.6B 量化模型可以在本地参与拼音候选生成；
- 支持全拼和多种双拼；
- 服务可仅监听本机，数据不必联网；
- 实现和测试入口完整，适合快速感受 AI 候选是否真的更好。

限制（均来自项目 README）：

- 不能与其他 Rime 输入方案结合，只能启用独立 `llm` schema；
- 输入太快可能漏字母；
- 长句可能不智能；
- 没有持久生词记忆，服务重启会丢失记忆；
- 每次输入经过 Rime Lua、curl、本地服务和模型，链路明显长于原生 translator。

因此它适合作为对照实验，不适合直接替换当前主力方案。来源：[LIME README](https://github.com/xushengfeng/lime)。

### 3. Cassotis：小型专用重排器的工程样板

Cassotis 不是 Rime 项目，但它展示了更合理的产品化路径：先用词典和统计语言模型生成候选，再用紧凑的前馈残差模型保守地调整 N-best；只有模型优势超过阈值才提升候选，并始终保留原引擎结果作为 fallback。模型离线训练后被导出为原生参数，运行时不启动 PyTorch、ONNX 或外部服务。

其项目自报的短词上下文基准中，v1.15.0 在 65,000 个样本上 Top-1 为 95.12%，P50 约 3.24 ms；长句 v1.17.0 的完整查询 P50 为 32 ms。两个基准使用作者小说语料，且长句数字不是逐键延迟，所以只能用来说明这种架构可行，不能与本配置直接横比。来源：[Cassotis README](https://github.com/shenmin/cassotis-ime)。

对本项目最有价值的不是复用它的模型，而是复用设计原则：

- Rime 继续负责拼音切分、词典召回和用户词典；
- 模型只看有限 N-best，工作量有上界；
- 采用 residual score 和提升阈值，证据弱时不改变原顺序；
- 为长句与短词上下文分别训练；
- 缓存公共特征，并设置硬延迟预算。

### 4. OpenIME：有代码和数据的经典神经 P2C

OpenIME 是论文 *Open Vocabulary Learning for Neural Chinese Pinyin IME* 的配套代码和处理后数据。论文把拼音到汉字视为不需要重排的 seq2seq，使用双向 LSTM encoder、attention decoder，并在用户选择后在线更新词表。论文报告在 TouchPal 数据上 Top-5 达到 89.7%，且在线词表适应明显改善效果。

问题是代码基于旧 Torch/OpenNMT，模型是完整 P2C 引擎而非 Rime filter，没有现代 macOS/Rime 集成，也不是今天意义上的轻量即插即用模型。适合作为训练目标、指标和在线适应算法的参考。来源：[论文](https://aclanthology.org/P19-1154/)、[代码](https://github.com/cooelf/OpenIME)。

### 5. AttnInput：更前沿，但不是“小模型现成方案”

AttnInput 把拼音特征通过侧网络注入 RWKV6，并使用拼音约束的 beam search。论文使用约 1.6B 参数主干和 0.5B 参数侧网络；在 RTX 4090D 上 beam size 16 约每 token 20 ms，四音节示例约 80 ms。它说明“长上下文状态缓存 + 拼音约束生成”是有前景的研究方向，但论文是匿名稿，当前检索到的版本没有公开代码或 Rime 集成，规模也大于这里期待的微型重排器。来源：[AttnInput PDF](https://00ffcc.tech/assets/pdf/attninput.pdf)。

## 论文给出的共同结论

### 统计模型与神经模型应融合

*Neural or Statistical: An Empirical Study on Language Models for Chinese Input Recommendation on Mobile* 的实验中，单独 n-gram 的 MAP 高于单独 NLM/RNN/LSTM，但统计与神经模型融合后更好；n-gram + NLM + word2vec 相对最佳单独统计模型的 MAP 提升 8.3%。这支持“保留 Octagram，神经模型只做补充分数”，而非完全替换现有引擎。来源：[论文](https://arxiv.org/abs/1907.05340)。

### 实时瓶颈是候选空间上的 softmax/解码

*Real-time Neural-based Input Method* 指出，大词表 softmax 是实时转换瓶颈；通过选择性词表和模型压缩可获得两个数量级的 softmax 加速，并在不损失精度时缩小 92% 模型体积。对应到 Rime，最自然的“选择性词表”就是先让 Rime 召回少量拼音合法候选，再让模型评分。来源：[论文](https://arxiv.org/abs/1810.09309)。

### 上下文和在线适应确实重要

*Chinese Pinyin Aided IME, Input What You Have Not Keystroked Yet* 将上一轮输入作为额外上下文；OpenIME 则利用用户每次选择这一天然标签在线更新词表。两者都说明模型输入至少应包含最近上屏文本，训练数据也应保留“拼音、候选、实际选择、前文”的事件结构。来源：[上下文 P2C 论文](https://arxiv.org/abs/1809.00329)、[OpenIME 论文](https://aclanthology.org/P19-1154/)。

## 推荐架构

### A. 近期：离线 AI 日志分析器

这是建议先实现的版本，不改实时输入链路：

```text
candidate_logs/*.csv
        │
        ▼
本地模型批处理 + 确定性规则校验
        │
        ├── 建议调整 custom_phrase 词频
        ├── 建议新增 pin_cand_filter 条目
        ├── 标出疑似召回失败/词典缺词
        └── 生成待人工审核的 patch
```

模型可先用 Qwen3-0.6B 验证流程；若中文判断不足，离线任务可换 1.7B/4B 量化模型，因为它不影响键盘延迟。Qwen3-0.6B 为 0.6B 参数、Apache-2.0；[`llama.cpp`](https://github.com/ggml-org/llama.cpp) 在 Apple Silicon 上支持 Metal、量化和本地 HTTP 服务。来源：[Qwen3-0.6B model card](https://huggingface.co/Qwen/Qwen3-0.6B)、[llama.cpp server](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md)。

当前日志有一个训练数据缺口：按 `;` 只记录“不满意的候选页”并清空输入，没有记录用户最终想要的正确文本。它足够辅助人工修频，但不足以自动训练监督重排器。后续若要训练，需要为事件补充 `event_id`，并把下一次人工确认的修正词或显式选择记录为 label。

### B. 中期：本地候选重排守护进程 PoC

```text
Rime 召回 Top-N
  + 最近 commit context
  + 当前拼音
        │
        ▼
本地 scorer（常驻、缓存、超时）
        │
        ▼
融合 Rime 分数与模型分数
        │
        ├── < 预算：返回新顺序
        └── 超时/异常：原顺序不变
```

关键要求：

- 只重排 Rime 已确认拼音合法的候选；
- 常驻模型并缓存 context state，禁止每次按键重新加载；
- 第一阶段只在音节边界或候选页稳定后触发，而非每个字母都推理；
- 总预算建议先设 15～25 ms，超时立即 fallback；
- 用记录的真实输入做 P50/P95/P99 延迟和 Top-1/Top-5 评测；
- 不让模型直接删除候选，只允许有限换位；
- 服务只绑定 loopback，不记录未脱敏的全局上下文。

`llama.cpp` server 支持量化模型、Apple Metal、completion probabilities 和 rerank endpoint，适合作为 PoC 服务。但通用 rerank endpoint 面向语义相关性，不等于拼音候选概率；正式评分应计算 `P(candidate | context, pinyin)`，或训练专用 pairwise classifier。来源：[llama.cpp README](https://github.com/ggml-org/llama.cpp)、[server README](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md)。

### C. 长期：原生 librime 微型重排插件

如果 PoC 证明收益稳定，最终形态应是 C++ `librime` filter/plugin，内嵌小型 ONNX/Core ML 模型或直接编译权重。这样能避免 Lua 启动子进程和 HTTP 往返。代价是需要维护自定义 librime/Squirrel 构建、签名、模型 ABI、崩溃隔离和升级兼容，开发成本明显高于配置层功能。

建议模型不是 0.6B LLM，而是以这些特征训练的微型 MLP/小 RNN：

- 前文最后 8～32 个字的字符/词 n-gram 分数；
- 当前拼音与候选长度、分词结构；
- Rime 原始 quality、候选类型、是否用户词；
- Octagram 搭配分数；
- 用户历史选择频率与时间衰减；
- 候选之间的差分特征。

这条路线与 Cassotis 的残差重排思想一致，也符合论文中“统计 + 神经融合”的证据。

## 建议的评测与进入条件

不要只凭几个例子判断模型。先从日志形成最小评测集：

| 指标 | 含义 |
| --- | --- |
| Recall@N | 正确词是否已被 Rime 放进前 N；先判断重排是否有机会解决 |
| Top-1 / Top-5 | 正确候选位置是否改善 |
| MRR | 正确候选平均倒数排名 |
| 回归率 | 原本正确 Top-1 被模型改错的比例 |
| P50/P95/P99 | 从按键到候选可见的增量延迟 |
| fallback 率 | 超时、模型不可用或置信不足时保留原排序的比例 |

推荐进入实时集成的门槛：

- 独立测试集上 Top-1 有稳定提升；
- 回归率足够低，并能用阈值进一步控制；
- P95 增量延迟不破坏连续输入体验；
- 模型停机、超时和异常时与当前行为完全一致；
- 日志和上下文均只保留在本机，且可明确关闭。

## 下一步建议

1. 用相同日志或句集记录万象模型的候选质量，并与保留的 `zh-moqi` 基线比较。
2. 扩充候选日志格式，使“不满意事件”最终能关联到用户实际想输入的文本。
3. 写一个离线分析器，把 CSV 转成可审核的 `custom_phrase` / `pin_cand_filter` 建议。
4. 单独安装 LIME + Qwen3-0.6B，测本机实际首候选质量和 P50/P95 延迟。
5. 只有第 4 步相对 Octagram 基线有明显收益时，再设计实时 reranker API 或原生插件。

## 资料索引

论文：

- [Neural or Statistical: An Empirical Study on Language Models for Chinese Input Recommendation on Mobile](https://arxiv.org/abs/1907.05340)
- [Real-time Neural-based Input Method](https://arxiv.org/abs/1810.09309)
- [Enabling Real-time Neural IME with Incremental Vocabulary Selection](https://aclanthology.org/N19-2001/)
- [Chinese Pinyin Aided IME, Input What You Have Not Keystroked Yet](https://arxiv.org/abs/1809.00329)
- [Open Vocabulary Learning for Neural Chinese Pinyin IME](https://aclanthology.org/P19-1154/)
- [Moon IME: Neural-based Chinese Pinyin Aided Input Method with Customizable Association](https://aclanthology.org/P18-4024/)
- [AttnInput: Advancing Context-Aware Pinyin Input with Efficient Language Model Integration](https://00ffcc.tech/assets/pdf/attninput.pdf)

代码和模型：

- [rime/librime](https://github.com/rime/librime)
- [lotem/librime-octagram](https://github.com/lotem/librime-octagram)
- [amzxyz/RIME-LMDG](https://github.com/amzxyz/RIME-LMDG)
- [rime/librime-predict](https://github.com/rime/librime-predict)
- [xushengfeng/lime](https://github.com/xushengfeng/lime)
- [shenmin/cassotis-ime](https://github.com/shenmin/cassotis-ime)
- [cooelf/OpenIME](https://github.com/cooelf/OpenIME)
- [Qwen/Qwen3-0.6B](https://huggingface.co/Qwen/Qwen3-0.6B)
- [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp)

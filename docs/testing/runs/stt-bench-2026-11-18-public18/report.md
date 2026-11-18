# 18 条公开音频：四引擎流式识别准确度

日期：2026-11-18。复用已有 AMI IHM 12 条、earnings22 6 条，共约 252.3 秒；每条独立启动，实时释放输入，EOF 完成后按参考文本计分。无新增模型或数据集下载。

| 引擎 | 总 WER | AMI WER | earnings22 WER | 失败 / 空输出 |
|---|---|---|---|---|
| apple | 11.64% | 9.04% | 12.72% | 0 / 0 |
| qwen3asr | 11.64% | 4.79% | 14.51% | 0 / 0 |
| parakeet | 17.14% | 12.23% | 19.20% | 1 / 0 |
| nemotron | 17.30% | 11.70% | 19.64% | 0 / 0 |

WER 为总编辑距离 / 总参考词数，按词加权；空输出按全文删除计分，失败有部分文本时照实际输出计分并另报失败数。参考文本来自本地 manifest，并未重新人工审校。

归一化统一为 NFKC、小写、统一英文弯引号、标点换空格、合并空白；保留数字写法和缩写差异。尚未实现原方案的数字/缩写语义归一化，因此这些差异可能计入错误。

配置沿用 quick5：Apple SpeechAnalyzer en-US volatileResults/fastResults；Qwen3-ASR 1.7B 8bit 1 秒 chunk / 30 秒上下文；Parakeet v2 MLX 默认 (256,256) context / depth 1，每秒推理；Nemotron 3.5 多语言 CoreML INT8，en-US，320 ms native chunk。

本轮修正 Parakeet 最后不足 1 秒数据批次的取样边界，保证每个输入样本只喂一次；5 分钟整秒音频不受此修正影响。各样本结束不加尾部静音：Qwen/Nemotron 调 EOF finish，Apple finalizeAndFinish；Parakeet 使用末次 stable+draft 快照。

仅是小规模公开数据验证，不能代表用户面试录音总体准确率，不测翻译/功耗/Gemma 并发，也不能直接满足原方案的替换门槛。

完整逐条参考稿与实际输出：[results.json](/Users/xiaohui/Downloads/cicada-asr-lab-20261117/bench/public18/results.json)。原始事件按引擎存于 [public18](/Users/xiaohui/Downloads/cicada-asr-lab-20261117/bench/public18)，执行脚本 run.py、评分脚本 score.py；模型版本与哈希复用 [models.lock.json](/Users/xiaohui/Downloads/cicada-asr-lab-20261117/bench/models.lock.json)。

## 每路错误率最高的 3 条

### apple / earnings22-001 / WER 28.8%

参考：As far as the capital allocation, the significant part of the capital we earned over last year, will be paid via dividends, then as I mentioned we still have some of the liabilities in our balance sheet that there is a significant excess of liabilities over receivables and this is also to be included in our cash flow funds.

输出：As far as the capital allocation, um, the the significant uh, part of the capital we uh, we earned uh, over last year, will be paid uh, via dividends. Then, as I mentioned, we still have some of the liabilities. Uh, in our balance with uh, there is a significant excess of liability of uh, liabilities uh, over receivables and this, this is also to be uh, included uh, in our cash flow funds.

### apple / ihm-041 / WER 21.4%

参考：ACTUALLY IS THE CODE ACCESSIBLE LIKE THE THE GUI STUFF THAT YOU'VE DONE YEAH

输出：Actually, is the code accessible, like the gooey stuff that you've done?

### apple / ihm-052 / WER 21.4%

参考：YEAH UH CHANGE THE CONTENTS OF THE SAME WINDOW LIKE FROM TRANSCRIPTION TO SUMMARY

输出：Yeah, it would change to contents of the same window. like from transcription to summary.

### qwen3asr / earnings22-004 / WER 18.3%

参考：Uh, and I think the cooperation that we have with with the units within our technical organization, with the skillset that they bring, uh, the cooperation between the commercial and technical parts, that will yield, uh, better control and better, um, uh, performance and execution going forward in- in- in all aspects, and not just commercial, I would say, but also from a customer experience perspective, uh, and a production perspective.

输出：And I think the cooperation that we have with with the unit within our technical organisation, with the skill set that they bring, cooperation between the commercial and technical parts, that will yield better control, better performance, and execution going forward in in in all aspects, and not just commercial, I would say, but also from a customer experience perspective. And the production perspective.

### qwen3asr / earnings22-005 / WER 17.9%

参考：So, so, um, uh, I- I- I wouldn't read, um, much more into that from China, but I do believe, uh, uh, our feeling is consistent with what we communicated in Q4, saying that, um, we expect China to be, uh, you know, flat to-slightly positive for us for the year, despite the continued, uh, uh, negative development of the fermented category in, um, in China.

输出：So I I wouldn't read much more into that from China, but I do believe our feeling is consistent with what we communicated in Q4, saying that we expect China to be you know flat to slightly positive for us for the year, despite the continued negative development of the fermented category. In in China.

### qwen3asr / earnings22-003 / WER 17.7%

参考：Uh, what influences our- our revenues are the digital sales as uh, then, the- the sales are each time the reporting is instant without the sub-distributor in the middle of the process, uh, and most of the sales occurred uh, for PC on all of the available PC platforms, there's obviously the Xbox digital, uh, sales and since Cyberpunk is non-existent on the Sony store front we we didn't report any revenues NSAs from- from this one.

输出：What influences our our revenues are the digital sales, as then the the sales are instant and the reporting is instant, without the sub distributor in the middle of the process, and most of the sales occurred for PC on all of the available PC platforms. There is obviously the Xbox digital sales, and since Cyberpunk is not existent on the Sony storefront, we we didn't report any. Revenues and sales from from this one.

### parakeet / ihm-043 / WER 31.2%

参考：SO IF THERE'S A DE SO IT'LL BE A CHOICE FROM THE MENU BUT YEAH EXACTLY

输出：So if there's a d so it'll be a choice for the menu.

### parakeet / earnings22-005 / WER 26.9%

参考：So, so, um, uh, I- I- I wouldn't read, um, much more into that from China, but I do believe, uh, uh, our feeling is consistent with what we communicated in Q4, saying that, um, we expect China to be, uh, you know, flat to-slightly positive for us for the year, despite the continued, uh, uh, negative development of the fermented category in, um, in China.

输出：So I wouldn't read much into that from China. But I believe our feeling is consistent with what we communicated in Q4, saying that we expect China to be flat to slightly positive for us for the year, despite the continued negative development of the fermented category in China.

### parakeet / earnings22-003 / WER 24.1%

参考：Uh, what influences our- our revenues are the digital sales as uh, then, the- the sales are each time the reporting is instant without the sub-distributor in the middle of the process, uh, and most of the sales occurred uh, for PC on all of the available PC platforms, there's obviously the Xbox digital, uh, sales and since Cyberpunk is non-existent on the Sony store front we we didn't report any revenues NSAs from- from this one.

输出：What influences our revenues are the digital sales as the saves are instant and the reporting is instant with the sub distributor of the process. And most of the sales occurred for PC on all of the available PC platforms. There is obviously the Xbox digital sales. And since Cyberpunk is non-existent on the Sony store front, we we didn't report any revenues, any sales from this one.

### nemotron / earnings22-005 / WER 28.4%

参考：So, so, um, uh, I- I- I wouldn't read, um, much more into that from China, but I do believe, uh, uh, our feeling is consistent with what we communicated in Q4, saying that, um, we expect China to be, uh, you know, flat to-slightly positive for us for the year, despite the continued, uh, uh, negative development of the fermented category in, um, in China.

输出：So II wouldn't read uh much more into that from China, but I do believe our feeling is consistent with what we communicated in Q four saying that we expect China to be flat to slightly positive for us for the year despite the continued negative development of the fermented category in China

### nemotron / earnings22-003 / WER 26.6%

参考：Uh, what influences our- our revenues are the digital sales as uh, then, the- the sales are each time the reporting is instant without the sub-distributor in the middle of the process, uh, and most of the sales occurred uh, for PC on all of the available PC platforms, there's obviously the Xbox digital, uh, sales and since Cyberpunk is non-existent on the Sony store front we we didn't report any revenues NSAs from- from this one.

输出：What influences our our revenues are the digital sales as the sales are instant and the reporting is instant without the subdistributor in the middle of the process, and most of the sales occurred for PC on all of the available PC platforms there is obviously the exbox digital sales and since cyberpunk is not existent on the sunny storefront we we didn't report any revenues and the sales from from this one

### nemotron / ihm-036 / WER 22.7%

参考：WE DON'T WE'RE NOT ACTUALLY SURE WHAT THE USER WANTS WITH IT BUT IT'S INTERESTING SO WHY NOT GIVE IT TO HIM

输出：I'm not actually sure what the user wants with it, but it's interesting so why not give it


## 观察与结论

- Apple 与 Qwen 总错误数同为 74 / 636，WER 11.64%。Qwen 的 AMI WER 较低（4.79% 对 9.04%），但 earnings22 较高（14.51% 对 12.72%）。不能仅凭总体相等说两者所有场景表现相同。
- Parakeet 当前配置 WER 17.14%，出现 1 次失败；earnings22-001 最后极短尾包在 parakeet-mlx 0.7.0 的 get_logmel / stft 中触发 `ValueError: [as_strided] Negative dimensions not allowed.`。保留该条部分输出计分，没有从分母移除，也未用重跑结果替换。
- Nemotron 当前 3.5 多语言 INT8 配置 WER 17.30%，删除错误 62 个，高于 Apple 的 23 个。这一结果仅针对当前模型、流式配置和本批短片段，不代表全部 Nemotron 变体。
- 前轮五分钟共同短语对比中，Nemotron 中位数提前约 0.37 秒；本轮准确度未优于 Apple。当前证据不支持替换 Apple；Qwen 可继续作为候选验证，Parakeet 需先处理流式尾包兼容性。
- 以上是 18 条、636 个参考词的小样本描述，没有独立测试集调参或统计显著性结论。数字/缩写尚未做语义归一化，WER 不能当成产品正式验收分数。

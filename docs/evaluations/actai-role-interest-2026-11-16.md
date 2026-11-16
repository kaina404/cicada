# 岗位兴趣短句案例检查

日期：2026-11-16

项目案例已保存。开发版实际知识库未修改：目标目录不在当前可写范围内。已生成待应用更新补丁。

## 静态检查

- PASS: reference_question_present
- PASS: short_sentences
- PASS: required_facts
- PASS: separate_question_routes
- PASS: other_knowledge_preserved

共 10 句；每句词数：12, 8, 11, 7, 11, 6, 10, 8, 9, 14。

## 实际应用验证

未执行。当前开发版仍将岗位兴趣问题路由到两分钟公司动机答案，不能据此宣称新答案通过端到端测试。补丁写入后应验证 “Why are you interested in this role?” 和 “What interests you about this position?” 使用短句案例，同时 “Why do you want to join ActAI?” 保留原有公司动机版本。

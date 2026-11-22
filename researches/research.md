# Pesquisa: literatura em torno do OpenDLQ

- **Data:** 2026-11-22
- **Pergunta:** existem papers que descrevem os problemas que o OpenDLQ ataca, e papers que descrevem soluções para eles?
- **Resposta curta:** não achei paper revisado por pares sobre DLQ em si. Existe literatura sólida sobre os problemas e as soluções que os mecanismos do OpenDLQ tocam (retry, falhas metaestáveis, agrupamento de falhas, automação de incidentes, entrega e verificação formal). O mapeamento entre os docs e os papers é **leitura minha**, não do projeto.

## 1. O que os docs afirmam e o que não citam

Fontes lidas: `README.md`, `docs/rfc/0001-opendlq.md`, `docs/principles.md`, `docs/guarantees.md`, `docs/state-machine.md`. Busca por `paper`, `arxiv`, `doi`, `ieee`, `acm`, `usenix`, `references` em `docs/`, `roadmap/` e `README.md`: **nenhuma referência externa**. Os únicos links `http` são URLs de exemplo de configuração (`loki.internal`, `grafana.internal`).

O RFC 0001 declara a base empírica do projeto:

> "The problems below show up repeatedly in operator reports (threads on r/aws, r/sysadmin and r/devops, and the open source tools listed under alternatives). There is no quantitative survey; the list is qualitative."

e trata a classificação automática como hipótese: "It treats automatic classification as the hypothesis to test."

Não li `architecture.md`, `flows.md`, `operations.md`, `scope.md` nem `docs/components/*.md`.

### Afirmações do projeto que a literatura toca

| Afirmação | Onde está | Seção deste documento |
|---|---|---|
| Retry nativo trata toda falha igual; retry de falha permanente só soma carga | `principles.md` #1, RFC "Central thesis" | 2.1, 2.2 |
| Mil mensagens com a mesma causa aparecem como mil itens | RFC "Context and problem" | 2.3, 3.3 |
| Circuit breaker por dependência, com probe e drain controlado | RFC "Goals", `components/transient-runner.md` | 3.2 |
| O breaker conta só falhas classificadas como transitórias | RFC "Risks" | 3.2 |
| Replay com idempotency key; entrega at-least-once via outbox | `guarantees.md` #3, RFC "Risks" | 4.1 |
| Garantias verificadas com especificações TLA+ | `guarantees.md` "Verification" | 4.2 |
| Runbooks com guardrails; humanos decidem falhas permanentes | `principles.md` #2 | 3.4 |
| Transitório x permanente como primeira decisão | `principles.md` #1 | 3.1 |

## 2. Papers sobre os problemas

### 2.1 Retry mal desenhado é fonte comum de bug

**Stoica et al., SOSP 2024, "If At First You Don't Succeed, Try, Try, Again...? Insights and LLM-informed Tooling for Detecting Retry Bugs in Software Systems".**
Estudo de problemas reais de retry em aplicações Java open source (Elasticsearch, Hadoop, HBase, Hive, Kafka) e a ferramenta WASABI (análise estática, LLM, injeção de falhas e testes unitários). Segundo o pôster dos autores, política de retry ruim responde por cerca de 2/3 dos bugs e mecanismo quebrado por cerca de 1/3. O estudo reporta 109 bugs em 8 sistemas.
*Relação:* sustenta a tese do RFC de que retry sem critério é problema, mas trata de código de retry, não de DLQ.

### 2.2 Retries sustentam falhas depois que o gatilho some

- **Bronson et al., HotOS 2021, "Metastable Failures in Distributed Systems".** Define falhas metaestáveis: um gatilho temporário e um ciclo de realimentação (retries, cache, caminho lento de erro) que mantém o sistema degradado mesmo depois do gatilho.
- **Huang et al., OSDI 2022, "Metastable Failures in the Wild".** Análise de post-mortems públicos. Segundo resumos secundários da busca: mais de 600 relatórios, 21 falhas metaestáveis, e pelo menos 4 de 15 grandes quedas da AWS na década atribuídas a esse tipo. Propõe dois tipos de gatilho e dois de amplificação.

*Relação:* é a base teórica para o risco que o RFC trata com breaker, `held` e drain em taxa controlada, e para a "Known objection" (nunca reenfileirar a DLQ sem saber por quê).

### 2.3 Falhas iguais parecem muitos problemas

**Glerum et al., SOSP 2009, "Debugging in the (Very) Large: Ten Years of Implementation and Experience" (Windows Error Reporting).**
Descreve o bucketing de relatórios de erro de cerca de um bilhão de máquinas: reports parecidos caem no mesmo bucket, e bugs são abertos automaticamente quando muitos caem no mesmo. O trabalho seguinte do DSN 2011 sobre crash graphs descreve o "second-bucket problem": um mesmo bug aparece em vários buckets pequenos.
*Relação:* é o problema que o `group_key` resolve. O risco de agrupamento fragmentado é real e vale como critério de teste.

### 2.4 Operação de incidentes é cara e pouco automatizada

**"How to Fight Production Incidents? An Empirical Study on a Large-scale Cloud Service", SoCC 2022 (Microsoft).**
Estudo de incidentes graves e post-mortems: causas, caminhos de resolução e onde a automação ajudaria.
*Relação:* contexto para "alerts without answers" e para o investimento em runbooks e enriquecimento.

## 3. Papers sobre as soluções

### 3.1 Classificar transitório x permanente

**Avizienis, Laprie, Randell, Landwehr, IEEE TDSC 2004, "Basic Concepts and Taxonomy of Dependable and Secure Computing".**
Taxonomia de falta, erro e falha. Pelo meu conhecimento ela classifica faltas por persistência (permanente e transitória), mas os trechos que a busca devolveu **não confirmaram** essa parte. Confirmar no PDF antes de citar.

### 3.2 Backoff, jitter e circuit breaker

- **"Resilient Microservices: A Systematic Review of Recovery Patterns, Strategies, and Evaluation Frameworks", arXiv 2512.16959.** Revisão de 26 estudos. Segundo o resumo: backoff sem jitter sincroniza os retries; jitter é forma padrão de reduzir tempestades de retry; o breaker prova a recuperação em estado half-open; limiares apertados demais reduzem a vazão.
- **AWS Builders' Library, "Timeouts, retries and backoff with jitter"** (prática, não é paper). Critica circuit breakers por criarem comportamento modal, difícil de testar e que pode alongar a recuperação.

*Relação:* o design `held` / probe / drain do OpenDLQ é um breaker com drain controlado. O RFC já cita o falso positivo do breaker e a mitigação (contar só falhas transitórias). A crítica da AWS é o contra-argumento a testar.

### 3.3 Agrupar por causa raiz e extrair contexto de logs

- **Glerum et al., SOSP 2009** (ver 2.3): bucketing como solução.
- **He et al., ICWS 2017, "Drain: An Online Log Parsing Approach with Fixed Depth Tree".** Parser online que converte linhas de log em templates com árvore de profundidade fixa. Versão posterior em arXiv 1806.04356. Relação: base para agrupar e extrair texto estável dos logs que o Enricher correlaciona.

### 3.4 Runbooks e automação de troubleshooting

- **AutoTSG, arXiv 2205.13457.** Estudo de mais de 4.000 troubleshooting guides e framework que os transforma em fluxos executáveis.
- **"Agentic Troubleshooting Guide Automation for Incident Management", arXiv 2510.10074.** Agente LLM (StepFly) que executa TSGs.

Ambos são preprints (venue não verificado). O OpenDLQ vai em sentido oposto por princípio: "Humans decide permanent failures", com runbook declarado antes e guardrails. Não achei evidência direta a favor ou contra essa escolha.

## 4. Garantias de entrega e verificação

### 4.1 Replay seguro e idempotência

**Wang et al., SIGMOD 2021, "Consistency and Completeness: Rethinking Distributed Stream Processing in Apache Kafka".**
Escritas idempotentes e transacionais para exactly-once em stream processing.
*Relação:* é analogia, não aplicação direta. O OpenDLQ garante at-least-once e transfere a idempotência ao consumidor pelo header contract. Não verifiquei paper específico sobre o padrão outbox.

### 4.2 Especificação formal

**Newcombe et al., CACM 2015, "How Amazon Web Services Uses Formal Methods".**
Uso de TLA+ e model checking em sistemas críticos da AWS. O OpenDLQ declara que as garantias são as propriedades das especificações TLA+ da máquina de estados, do outbox e da detecção de recuperação, além de testes de propriedade em Go.
*Complemento:* Brooker e Desai, CACM 2025, "Systems Correctness Practices at AWS", relata que engenheiros tiveram dificuldade para aprender TLA+ quando o uso se expandiu. Visto só na busca.

## 5. Sobre DLQ em si

Duas buscas (padrão e estendida) só devolveram guias de praticantes, documentação de brokers e:

- Um relato de experiência em arXiv (2610.06890) sobre um pipeline de ML industrial com redrive automático para falha transitória e alerta para persistente. Os autores reportam redução de 60% no tempo médio de resolução. É relato de experiência, **o número é dos autores**, não de estudo controlado.
- Uma patente que usa picos de DLQ como sinal de failover (invenção, não evidência de eficácia).

Não achei estudo empírico de um plano de controle de DLQ como o OpenDLQ. As promessas centrais (classificar antes de agir; `held` não contar como tentativa; breaker contar só transitórias) **não têm validação publicada** que eu tenha encontrado.

## 6. Leituras complementares (vistas apenas na busca)

- Formal Analysis of Metastable Failures in Software Systems, arXiv 2510.03551.
- Formal analysis de falhas metaestáveis em storage replicado, arXiv 2309.16181.
- Artigo HotNets 2025 sobre modelo de fila para retry storm.
- Marc Brooker, blog sobre falhas metaestáveis (prática).

## 7. Limites e próximos passos

- Li **trechos devolvidos pela busca**, não os PDFs completos. Os números citados vêm de resumos, do pôster dos autores ou de fontes secundárias.
- Os IDs do arXiv vêm das listas de resultados e não foram abertos um a um.
- **DeepLog** (detecção de anomalia em logs) não foi verificado e ficou de fora.
- A classificação de persistência em Avizienis et al. não foi confirmada.
- Não li `architecture.md`, `flows.md`, `operations.md`, `scope.md` nem os docs de componentes. `scope.md` tem "open questions" que podem apontar onde falta evidência.

Próximos passos sugeridos: abrir os PDFs de Stoica (SOSP 2024), Huang (OSDI 2022) e Glerum (SOSP 2009) para confirmar números; ler `scope.md` e `components/transient-runner.md`; decidir quais afirmações do RFC merecem referência.

## Referências

1. Stoica et al. SOSP 2024, retry bugs: [pôster](https://bastoica.github.io/files/posters/2024_sosp_poster.pdf) · [Microsoft Research](https://www.microsoft.com/en-us/research/?p=1068147)
2. Bronson et al. HotOS 2021, Metastable Failures in Distributed Systems: [registro](https://pure.psu.edu/en/publications/metastable-failures-in-distributed-systems/)
3. Huang et al. OSDI 2022, Metastable Failures in the Wild: [USENIX](https://usenix.org/conference/osdi22/presentation/huang-lexiang)
4. Glerum et al. SOSP 2009, Debugging in the (Very) Large: [PDF](https://cs.uwaterloo.ca/~m2nagapp/courses/CS846/1171/papers/glerum_sosp09.pdf)
5. Crash graphs, DSN 2011: [PDF](https://www.cse.ust.hk/%7Ehunkim/images/4/45/Crash_graphs_dsn2011.pdf)
6. How to Fight Production Incidents? SoCC 2022: [Microsoft Research](https://www.microsoft.com/en-us/research/?p=881646)
7. Avizienis et al. IEEE TDSC 2004: [registro](https://drum.lib.umd.edu/handle/1903/6459)
8. Resilient Microservices, revisão sistemática: [arXiv 2512.16959](https://arxiv.org/pdf/2512.16959)
9. AWS Builders' Library, timeouts, retries and backoff with jitter: [artigo](https://aws.amazon.com/builders-library/timeouts-retries-and-backoff-with-jitter)
10. Drain, ICWS 2017: [PDF](https://pinjiahe.github.io/files/pdf/research/ICWS17.pdf) · [arXiv 1806.04356](https://arxiv.org/pdf/1806.04356)
11. AutoTSG: [arXiv 2205.13457](https://arxiv.org/pdf/2205.13457)
12. Agentic Troubleshooting Guide Automation: [arXiv 2510.10074](https://arxiv.org/html/2510.10074)
13. Wang et al. SIGMOD 2021, Kafka: [DBLP](https://dblp.dagstuhl.de/rec/conf/sigmod/WangCDGCSRBCMMR21.html)
14. Newcombe et al. CACM 2015: [artigo](https://cacm.acm.org/magazines/2015/4/184701-how-amazon-web-services-uses-formal-methods/fulltext)
15. Brooker e Desai, CACM 2025: [artigo](https://cacm.acm.org/practice/systems-correctness-practices-at-amazon-web-services)
16. Relato de experiência, pipeline de ML com redrive: [arXiv 2610.06890](https://arxiv.org/pdf/2610.06890)
17. Formal analysis de falhas metaestáveis: [arXiv 2510.03551](https://arxiv.org/pdf/2510.03551) · [arXiv 2309.16181](https://arxiv.org/html/2309.16181v2)

# RFC 0001: OpenDLQ

[English](0001-opendlq.md)

- **Status:** Rascunho
- **Autor:** Yuri Costa
- **Criado em:** 2026-10-27

Este RFC registra por que o OpenDLQ existe e as decisões por trás dele. O design em si fica nos docs por tema, listados abaixo. Quando o design muda, os docs por tema mudam; este RFC registra o raciocínio.

## Resumo

O OpenDLQ é um plano de controle para mensagens em dead-letter queues. Ele lê a DLQ, classifica cada mensagem como transiente ou persistente, recupera as transientes sem envolvimento humano e expõe as persistentes, agrupadas por causa, para um operador decidir. Toda ação fica registrada. Sobre esse núcleo há uma camada de gerenciamento genérica: analytics, custo, tendências, reincidência e purge.

O OpenDLQ não substitui o broker. Ele roda sobre Kafka, SQS ou RabbitMQ.

## Contexto e problema

Uma DLQ guarda mensagens que o consumer não conseguiu processar. O broker move a mensagem para lá, ou o consumer publica nela. Nos dois casos, a DLQ é só armazenamento. O que acontece depois depende das ferramentas e do processo de cada time.

Os problemas abaixo aparecem com frequência em relatos de operação (threads de r/aws, r/sysadmin e r/devops, e as ferramentas open source listadas em alternativas). Não há levantamento quantitativo; a lista é qualitativa.

- **Falta de contexto.** A DLQ guarda o payload. Em geral não guarda a exceção, o consumer que falhou, o número de tentativas ou a dependência envolvida.
- **Nenhuma distinção de causa.** Uma mensagem que falhou porque uma dependência ficou fora por pouco tempo fica ao lado de uma mensagem com schema inválido. A primeira só precisa de retry. A segunda nunca vai ter sucesso.
- **Replay manual.** O replay é um script ou um botão de redrive, em geral sem chave de idempotência, sem registro de quem executou, sem ordem e sem limite de vazão.
- **Nenhuma agregação.** Mil mensagens com a mesma causa aparecem como mil itens, não como um problema.
- **Nenhuma auto-recuperação.** O caso mais relatado é dependência instável. A solução é esperar e tentar de novo, mas isso exige uma pessoa.
- **Alerta sem resposta.** Alertas de profundidade existem (CloudWatch, Datadog, cron). O relato recorrente é que o alerta dispara e a investigação começa do zero.

O retry nativo dos brokers (SQS redrive, retry topics no Kafka, dead-letter exchanges no RabbitMQ) retenta N vezes seguidas. Ele não distingue causas, não agrega, não registra ações e não para quando a dependência inteira está fora.

## Objetivos

- Classificar toda mensagem como transiente ou persistente, por header, regra ou inferência.
- Recuperar falhas transientes sem envolvimento humano: retry com backoff, circuit breaker por dependência, drenagem controlada quando a dependência volta.
- Expor falhas persistentes agrupadas por causa, com contexto completo: erro, consumer, tentativas, payload, logs correlacionados.
- Permitir replay seguro: uma mensagem ou um lote, com chave de idempotência, com transformação opcional do payload.
- Permitir que operadores declarem runbooks para causas persistentes conhecidas, com guardrails, para tratamento automático.
- Registrar toda ação: quem, o quê, quando, resultado.
- Fornecer analytics completo: funil de resolução, custo, tendência, reincidência, por causa, consumer e período.
- Configurar tudo de forma declarativa, versionada e aplicada por CLI, com API e UI como alternativas equivalentes.
- Manter o núcleo genérico. O que depende do domínio entra por pontos de extensão.

Os não-objetivos estão no [roadmap](../roadmap.pt-BR.md#não-objetivos).

## Tese central

Toda falha de processamento tem uma de duas naturezas, e o tratamento correto é oposto em cada uma. Tratar as duas do mesmo jeito produz um de dois erros: retentar tudo sobrecarrega uma dependência indisponível, e não retentar nada aciona uma pessoa por um timeout de 30 segundos.

Por isso o OpenDLQ faz da classificação a primeira etapa, não uma etapa manual posterior. Veja [classificação](../classification.pt-BR.md).

## Design

| Tema | Documento |
| --- | --- |
| Princípios | [principles.pt-BR.md](../principles.pt-BR.md) |
| Classificação e contrato de headers | [classification.pt-BR.md](../classification.pt-BR.md) |
| Retry, circuit breaker, sonda, drenagem | [recovery.pt-BR.md](../recovery.pt-BR.md) |
| Runbooks | [runbooks.pt-BR.md](../runbooks.pt-BR.md) |
| Funil, custo, reincidência, exportação | [analytics.pt-BR.md](../analytics.pt-BR.md) |
| Alertas | [alerts.pt-BR.md](../alerts.pt-BR.md) |
| Configuração declarativa | [configuration.pt-BR.md](../configuration.pt-BR.md) |
| Ações de operador, logs correlacionados, purge | [operations.pt-BR.md](../operations.pt-BR.md) |
| Controllers, máquina de estados, plugins, consistência | [architecture.pt-BR.md](../architecture.pt-BR.md) |
| Casos de uso | [use-cases.pt-BR.md](../use-cases.pt-BR.md) |
| Escopo da V0, milestones, questões em aberto | [roadmap.pt-BR.md](../roadmap.pt-BR.md) |

## Alternativas consideradas

| Alternativa | Limitação |
| --- | --- |
| Retry nativo do broker (SQS redrive, Kafka retry topics, RabbitMQ DLX) | Retenta sem distinguir causas. Não abre circuito. Não agrega. Não registra ações. |
| Scripts de republish (`sqsmover` e similares) | Sem idempotência, sem registro, sem ordem, sem limite de vazão. |
| Retry dentro do consumer (Resilience4j, Kafka Cascade, KDLQ) | Cobre falha transiente curta. Bloqueia a partição enquanto espera. Sem visão central. |
| Browser de DLQ com edição e redrive (DLQ Revive, UIs internas) | Cobre visibilidade e replay auditado. Não classifica, não se recupera sozinho, não mede custo. |
| Observabilidade sobre a DLQ (CloudWatch, Datadog, Sentry Queues) | Mede profundidade, idade e tentativas. Não age. Não classifica. |
| Workflow engine (Temporal, Cadence) | Resolve retry durável e estado. Exige reescrever os consumers como workflows. |

O OpenDLQ não compete com retry no código nem com alerta de profundidade. Ele trata o que sobreviveu ao retry curto do consumer.

### Objeção conhecida

Um argumento comum em discussões de operação: nunca reenfileirar DLQ automaticamente; reenfileirar só depois de saber a causa, porque (a) a dependência voltou ou (b) o bug foi corrigido.

O OpenDLQ aceita o argumento. A sonda é o critério (a) automatizado: o OpenDLQ reenfileira porque uma sonda confirmou que a dependência responde, não porque passou tempo. O critério (b) continua humano: uma falha persistente nunca é retentada sozinha, a não ser que um operador tenha declarado a decisão num runbook.

### Sobre a ausência de ferramenta padrão

Relatos de operação sugerem que cada time constrói a própria ferramenta de DLQ. Isso é compatível com demanda não atendida e também com um problema que cada time prefere resolver localmente. Este projeto não assume qual das duas é verdadeira. Trata a classificação automática como a hipótese a testar.

## Riscos

- **Replay sem idempotência no consumer duplica efeitos colaterais.** Mitigação: o contrato de headers é documentado, e a V0 inclui um consumer de exemplo que o implementa. Sem o contrato, o replay não é seguro.
- **Classificação errada.** Uma falha transiente marcada como persistente só espera uma pessoa. Uma falha persistente marcada como transiente consome os retries e depois vai para uma pessoa. O segundo caso é limitado pelo máximo de retries.
- **Falso positivo do circuit breaker.** Vinte mensagens com o mesmo erro de validação podem parecer uma dependência indisponível. Mitigação: o breaker conta só falhas classificadas como transientes.
- **Ordenação.** Um replay em lote de mensagens com a mesma chave de partição precisa manter a ordem original. A V0 ordena por `(partition_key, offset)` ao drenar. A ordem entre chaves diferentes não é garantida.
- **Volume.** Milhões de mensagens enchem o Postgres. Fora da V0. O store é substituível.

# OpenDLQ

**O plano de controle aberto para dead-letter queues.**
Recupera o que se resolve sozinho, explica o que não se resolve e mede tudo.

[English](README.md)

> **Status:** fase de design. A arquitetura está definida no [RFC 0001](docs/rfc/0001-opendlq.pt-BR.md). A primeira versão usa Kafka e ainda não foi construída. Tudo abaixo descreve o design planejado, não funcionalidades prontas.

---

## O problema

Uma dead-letter queue (DLQ) guarda mensagens que o consumer não conseguiu processar. É só isso que ela faz. O que acontece depois depende de scripts, dashboards e da memória de cada time.

Na prática, os mesmos problemas se repetem:

- **Falta de contexto.** A DLQ guarda o payload, mas em geral não guarda o erro, o consumer que falhou, o número de tentativas ou a dependência envolvida.
- **Nenhuma distinção de causa.** Uma mensagem que falhou porque uma dependência ficou fora por 30 segundos fica ao lado de uma mensagem com schema inválido. A primeira só precisa de retry. A segunda nunca vai ter sucesso.
- **Replay manual.** O replay é um script ou um botão de "redrive", em geral sem idempotência, ordem, limite de vazão ou registro de quem executou.
- **Nenhuma agregação.** Mil mensagens com a mesma causa parecem mil problemas.
- **Alerta sem resposta.** O alerta de profundidade dispara e a investigação começa do zero.

O retry nativo dos brokers (SQS redrive, retry topics no Kafka, dead-letter exchanges no RabbitMQ) retenta N vezes seguidas. Ele não sabe por que a mensagem falhou.

## O que o OpenDLQ faz

O OpenDLQ funciona sobre o broker que você já usa. Ele não substitui o broker.

Ele lê a DLQ e classifica cada mensagem em um de dois tipos:

| | Transiente | Persistente |
| --- | --- | --- |
| Causa | O ambiente: dependência fora, timeout, rate limit, lock | A mensagem ou o código: schema inválido, regra de negócio, bug |
| Retry resolve? | Sim, com tempo | Não |
| O que o OpenDLQ faz | Recupera automaticamente | Agrupa pela causa raiz e espera uma decisão |

A partir daí, ele atua em três frentes:

**Recupera** o que se resolve sozinho
- Retry com backoff exponencial e jitter.
- Circuit breaker por dependência. Quando muitas mensagens diferentes falham contra a mesma dependência, o OpenDLQ para de retentar, segura o backlog, testa a dependência e drena o backlog com vazão controlada quando ela volta.
- Runbooks: o operador declara como tratar uma falha persistente conhecida (transformar e reenviar, rotear, descartar), com guardrails como limite de vazão, aprovação nas primeiras execuções e data de expiração.

**Explica** o que não se resolve
- Agrupa falhas persistentes pela causa raiz.
- Correlaciona cada mensagem com os logs da aplicação que a geraram (Elasticsearch, Loki, CloudWatch Logs, Datadog Logs) por trace id e ids de correlação.
- Replay seguro: uma mensagem ou um lote, com chave de idempotência, respeitando a chave de partição original, com transformação opcional do payload.
- Log de auditoria completo: quem fez o quê, quando e com qual resultado.
- Alertas com contexto, declarados como código. Alertas operacionais vão para quem está de plantão; alertas de reincidência e custo vão para quem define prioridades.

**Mede** tudo
- Funil de resolução: quantas mensagens se recuperaram sozinhas, foram reprocessadas por operador, foram tratadas por runbook, foram descartadas ou continuam abertas.
- Idade por mensagem, não só profundidade da fila.
- Custo por causa e por consumer (armazenamento, replays, tempo de operador).
- Tendência e reincidência: a mesma causa voltando depois de tratada.
- Métricas e traces via OpenTelemetry (OTLP), mais um endpoint Prometheus, para montar dashboards e alertas nas ferramentas que você já usa.
- Purge com política: TTL por consumer ou por causa, arquivamento antes de apagar. O log de auditoria nunca é apagado.

## Princípios de design

1. **Nenhuma mensagem se perde. Nenhuma decisão é aplicada duas vezes.**
2. **Humanos decidem falhas persistentes.** A automação só executa o que um operador declarou.
3. **Declarativo primeiro.** O que não está em arquivo é drift.
4. **Plugável nas bordas, fixo no núcleo.**
5. **Sobre o seu broker, nunca no lugar dele.**
6. **Um só caminho para humanos e agentes.** Nenhuma API privilegiada.

O raciocínio por trás de cada princípio está em [docs/principles.pt-BR.md](docs/principles.pt-BR.md).

## Documentação

| Tema | |
| --- | --- |
| [Princípios](docs/principles.pt-BR.md) | As regras que decidem trade-offs |
| [Classificação](docs/classification.pt-BR.md) | Transiente vs. persistente, e o contrato de headers |
| [Recuperação](docs/recovery.pt-BR.md) | Retry, circuit breaker, sonda, drenagem controlada, idempotência |
| [Runbooks](docs/runbooks.pt-BR.md) | Automatizar falhas persistentes conhecidas, com guardrails |
| [Analytics](docs/analytics.pt-BR.md) | Funil de resolução, custo, reincidência, exportação OpenTelemetry |
| [Alertas](docs/alerts.pt-BR.md) | Alertas declarados com contexto, para dois públicos |
| [Configuração](docs/configuration.pt-BR.md) | Recursos declarativos, `diff`, `apply`, drift |
| [Operação](docs/operations.pt-BR.md) | Ações de operador, logs correlacionados, auditoria, purge |
| [Arquitetura](docs/architecture.pt-BR.md) | Controllers, máquina de estados, plugins, consistência |
| [Casos de uso](docs/use-cases.pt-BR.md) | Como a mistura de falhas muda por cenário |
| [Roadmap](docs/roadmap.pt-BR.md) | Escopo da V0, milestones, não-objetivos, questões em aberto |
| [RFC 0001](docs/rfc/0001-opendlq.pt-BR.md) | Por que o OpenDLQ existe e as alternativas consideradas |

## Licença

Apache License 2.0. Veja [LICENSE](LICENSE).

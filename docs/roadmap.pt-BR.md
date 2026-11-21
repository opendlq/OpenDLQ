# Roadmap

[English](roadmap.md)

## V0

A V0 está pronta quando a demo abaixo roda de ponta a ponta sem nenhum passo manual no meio.

**Escopo**

- Kafka como único broker, com Redpanda no desenvolvimento local.
- Postgres como state store.
- CLI e API. Sem UI.
- Classificação por header, regra e inferência.
- Retry, circuit breaker, sonda e drenagem controlada.
- Runbooks com guardrails.
- Ações de operador: listar por causa, inspecionar, reclassificar, reprocessar, editar e reprocessar, descartar.
- Analytics e reincidência como SQL sobre o state store, expostos em `/analytics`, `/metrics` e OTLP.
- Um plugin de provedor de logs sobre um arquivo local, como referência. Integrações reais vêm depois da V0.

**Fora da V0:** múltiplos brokers, multi-tenant, UI, autenticação.

**Demo**

Um produtor sintético publica eventos genéricos em `events`. Um consumer de exemplo chama um serviço fake `dep` via HTTP e publica falhas em `events.dlq` com o contrato de headers.

1. O operador derruba `dep`. O OpenDLQ detecta o padrão, abre o circuito e segura o backlog.
2. O operador sobe `dep`. A sonda passa. O backlog drena em ordem a 50 msg/s.
3. O produtor injeta 5% de payloads inválidos. Eles aparecem agrupados por causa. O operador corrige um pela API e reprocessa, e descarta os demais com motivo.
4. A mesma causa inválida volta pela terceira vez. O alerta de reincidência dispara.
5. O log de auditoria mostra todas as ações.

**Milestones**

1. **Fundação.** Docker Compose com Redpanda e Postgres. Produtor sintético. Consumer de exemplo com o contrato de headers. Serviço `dep` com endpoint para derrubar e subir.
2. **Collector e store.** Consumir a DLQ, gravar com metadata, commitar o offset depois. Migração do schema.
3. **Classificação.** Header, regras YAML, inferência por repetição.
4. **Retry e replay.** Retries agendados. Publisher com outbox, headers de idempotência e ordem de partição. Detecção de recuperação.
5. **Circuit breaker e sonda.** Detecção por padrão, estado `held`, canário, drenagem com limite de vazão.
6. **Operador.** Agrupamento por causa, reclassificar, reprocessar (uma e lote), editar payload, descartar com motivo, auditoria.
7. **Runbooks.** Match, ações, guardrails, dry run.
8. **Analytics e reincidência.** Rollups, `/analytics`, exportação OpenTelemetry, detecção de episódios, alertas.
9. **Escrita.** README com a demo gravada, docs atualizados, questões em aberto respondidas.

Cada milestone termina com um teste de integração contra o ambiente Compose.

## Depois da V0

- Sources e sinks para SQS, RabbitMQ e Pub/Sub.
- Provedores de log reais: Elasticsearch/OpenSearch, Loki, CloudWatch Logs, Datadog Logs.
- UI.
- Autenticação e multi-tenant.
- Store colunar para analytics via CDC.
- Contrato de headers e schemas dos recursos publicados como especificação independente.

## Não-objetivos

- Substituir ou implementar um broker.
- Ordenação global de mensagens reprocessadas. Ordenação por chave de partição é objetivo; ordenação global não é.
- Decidir sozinho como corrigir uma falha persistente.
- Substituir sua stack de logs ou de observabilidade. O OpenDLQ lê dela; não armazena logs.

## Questões em aberto

- [ ] Detecção de recuperação padrão: `ack` ou `silence`?
- [ ] Canário: mensagem segurada mais antiga ou mais recente? A mais antiga drena em ordem; a mais recente tem mais chance de ainda ser válida.
- [ ] Edição de payload antes do replay: JSON Patch ou substituição completa?
- [ ] Um endpoint agrupado (`GET /failures?group_by=reason`) basta para a V0 sem UI?

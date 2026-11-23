# Pesquisa: contrato comum para o Log Provider

- **Data:** 2026-11-23
- **Pergunta:** que campos Sentry, Datadog, Elastic (ECS, Logstash, Kibana), OpenTelemetry, Loki e CloudWatch usam para guardar um erro, e dá para definir um contrato único que o OpenDLQ use para mostrar "esse erro aconteceu, com esse log e esse stack trace"?
- **Resposta curta:** dá. Os sistemas guardam o erro de três formas diferentes, então o contrato fica no menor denominador comum e cada provider traduz a sua origem. O mapeamento e as decisões abaixo são **leitura minha** da documentação oficial, não algo que os docs do projeto já definam.

Contexto no projeto: `docs/plugins.md` define o Log Provider como "Correlation IDs + time window → logs", e `docs/components/enricher.md` define o que é guardado em `enrichments.data` (limite de 16 KB, extração por JSON path).

## 1. O que cada sistema guarda

| Canônico | Sentry (REST) | Datadog | Elastic ECS (Logstash, Kibana) | OTel | Loki / CloudWatch |
| --- | --- | --- | --- | --- | --- |
| ID | `event_id` (32 hex) | `data[].id` | `_id` do documento | n/a | CW: `eventId` |
| Hora | `timestamp` (RFC 3339 ou epoch s) | `attributes.timestamp` | `@timestamp` | `Timestamp` (uint64 ns) | Loki: ns em string. CW: `timestamp` em ms |
| Nível | `level` (`fatal`…`debug`) | `status` | `log.level` | `SeverityText` / `SeverityNumber` (ERROR = 17–20) | só dentro da linha |
| Serviço | `server_name` / tag | `service` | `service.name` | `service.name` no Resource* | label do stream / `logStreamName` |
| Mensagem | `title` | `message` | `message` | `Body` | linha / `message` (string opaca) |
| Tipo do erro | `exception.values[].type` | `error.kind` | `error.type` | `exception.type` | só dentro da linha |
| Mensagem do erro | `exception.values[].value` | `error.message`* | `error.message` | `exception.message` | só dentro da linha |
| Stack trace | `stacktrace.frames[]` estruturado, **mais antigo primeiro** | `error.stack` (string)* | `error.stack_trace` (string) | `exception.stacktrace` (string) | só dentro da linha |
| Trace | `contexts.trace.trace_id`** | `trace_id` | `trace.id` | `TraceId` | só dentro da linha |

\* Não confirmado literalmente na página lida. \*\* Aparece só no exemplo de resposta REST.

Detalhes que importam na implementação:

- **Sentry.** `exception.values[]` exige `type` ou `value`. Cada frame exige `filename`, `function` ou `instruction_addr`, e tem `lineno`, `in_app`. A resposta REST usa camelCase (`lineNo`, `inApp`, `absPath`), diferente do payload do SDK (snake_case). O provider lê o REST.
- **Datadog.** `POST /api/v2/logs/events/search` aceita `filter.query`, `filter.from`, `filter.to`, `page.limit` (padrão 10) e `page.cursor`. A resposta traz `data[].attributes` e `meta.page.after`. Permissão: `logs_read_data`.
- **ECS.** `error.stack_trace` é `wildcard` no mapping, mas o cliente envia uma string. No Logstash 8 todos os plugins usam ECS v8 por padrão (`ecs_compatibility`). Kibana é uma interface sobre o Elasticsearch.
- **OTel.** É um modelo de dados, não um store, então não há API de consulta. `exception.type` ou `exception.message` é obrigatório (um dos dois). `exception.stacktrace` é string "in the natural representation for the language runtime".
- **Loki.** `GET /loki/api/v1/query_range` devolve `data.result[].stream` (labels) e `values` como pares `[ns, linha]`. Padrão de `limit`: 100.
- **CloudWatch.** `FilterLogEvents` devolve até 10.000 eventos ou 1 MB por página, com `nextToken` (expira em 24 h). Filtro por campo JSON: `{ $.requestId = "abc" }`. Limite de 5 a 25 TPS por região, não ajustável.

## 2. O que isso muda no contrato

1. **Três grupos.** O Sentry guarda o erro estruturado. Datadog, Elastic e OTel guardam log com campos padrão. Loki e CloudWatch guardam uma linha opaca, sem campo de erro. Para esses dois últimos, o `extract` por JSON path do `enricher.md` continua necessário.
2. **Stack trace é string em 3 dos 4 que têm o campo.** Só o Sentry estrutura frames, e na ordem oposta à de um trace de Java. O contrato guarda sempre a string e aceita `Frames` como opcional.
3. **Só o trace ID é padrão em todos.** `x-request-id` e similares dependem do nome do campo que cada time usa. O mapeamento de header para campo fica na config do Provider.
4. **O Sentry não busca evento por correlation ID.** Os endpoints de evento só aceitam `event_id`. A busca por tag passa pelo endpoint de issues com `query`, e a sintaxe de tag não está documentada nas páginas lidas. A documentação recomenda webhook em vez de polling.
5. **Os limites variam muito.** O core deve pedir poucas entradas (algo como 20), o que já cabe no limite de 16 KB do `enrichments.data`.

## 3. Contrato proposto

```go
type LogProvider interface {
    Query(ctx context.Context, q Query) (Result, error) // ErrNotFound → not_found
}

type Query struct {
    TraceID  string            // hex de 32, extraído do traceparent
    IDs      map[string]string // x-request-id etc.; o provider traduz p/ o campo da origem
    From, To time.Time
    Limit    int
}

type Result struct {
    Entries []Entry
    Link    string
}

type Entry struct {
    ID, Service, Message string
    Time                 time.Time // sempre UTC
    Level                string    // debug|info|warn|error|fatal
    TraceID, SpanID      string
    Error                *Error
    Raw                  json.RawMessage // registro original, alimenta o `extract`
}

type Error struct {
    Type, Message string
    Stack         string  // texto como a origem entrega
    Frames        []Frame // opcional; mais recente primeiro
}

type Frame struct {
    File, Function string
    Line           int
    InApp          bool
}
```

Status do enrichment: `ErrNotFound` vira `not_found`. Qualquer outro erro ou timeout vira `unavailable`. Retry, timeout, `reuse_window` e o limite de tamanho continuam no Enricher do core, como já está no `enricher.md`.

Na tela, cada ocorrência vira um card: `Type: Message`, hora, serviço, as linhas de log de nível `warn` para cima, o stack colapsável e o link para a origem. Tudo cabe no `enrichments.data`.

## 4. Decisões em aberto

- **Normalização.** O provider preenche os campos canônicos. O `extract` da config do Consumer sobrescreve ou preenche o que faltar, que é o caso de Loki e CloudWatch. Hoje o `extract` só alimenta `data`, então isso estende o que o `enricher.md` define.
- **Ordem dos frames.** Mais recente primeiro, o que casa com o `stack[0]` do `stack_top` no `enricher.md`. O provider do Sentry inverte a lista.
- **Correlação.** O core converte o `traceparent` em `TraceID` e manda os outros headers em `IDs`. O provider traduz cada um por um `correlation_fields` na spec do Provider, por exemplo `x-request-id: attributes.request_id`.
- **Nível do plugin.** O `plugins.md` coloca o Log Provider no nível 3 (adapters compilados, mantidos pelo projeto). Para terceiros criarem o provider sem fork, ele precisa ir para o nível 2 (out-of-process, gRPC).

## 5. O que não foi verificado

- **Datadog:** só `error.kind` foi lido literalmente. O resto de `error.*` veio de um resumo da página. O tipo de `trace_id` aparece como number na página, e a sintaxe de busca por atributo não estava nas páginas lidas.
- **OTel:** `service.name` e o encoding OTLP/JSON não foram confirmados, porque as páginas de resource e file exporter retornaram 404.
- **Loki:** LogQL (`| json`, filtros) e os limites do servidor não foram lidos.
- **Elasticsearch:** `_search`, `search_after` e as consultas por `term` e `range` não foram lidos, só as páginas do ECS.
- **Sentry:** a página de exception retornou 404, então usei a especificação de `errors.md`. A posição de `contexts.trace.trace_id` vem só de um exemplo de resposta.
- **Fora do escopo:** Splunk, New Relic, Honeycomb e Grafana Tempo.

## 6. Fontes

- [Sentry: Errors wire format](https://develop.sentry.dev/sdk/telemetry/errors/)
- [Sentry: Stacktrace interface](https://develop.sentry.dev/sdk/data-model/event-payloads/stacktrace/)
- [Sentry: Event payloads](https://develop.sentry.dev/sdk/data-model/event-payloads/)
- [Sentry API: Retrieve an event](https://docs.sentry.io/api/events/retrieve-an-event-for-a-project/)
- [Datadog: Standard attributes](https://docs.datadoghq.com/logs/log_configuration/attributes_naming_convention/)
- [Datadog API: Search logs](https://docs.datadoghq.com/api/latest/logs/)
- [Elastic ECS: error](https://www.elastic.co/guide/en/ecs/current/ecs-error.html)
- [Elastic ECS: log](https://www.elastic.co/guide/en/ecs/current/ecs-log.html)
- [Elastic ECS: tracing](https://www.elastic.co/guide/en/ecs/current/ecs-tracing.html)
- [Logstash: ECS compatibility](https://www.elastic.co/guide/en/logstash/current/ecs-ls.html)
- [OpenTelemetry: Logs data model](https://opentelemetry.io/docs/specs/otel/logs/data-model/)
- [OpenTelemetry: exception attributes](https://opentelemetry.io/docs/specs/semconv/registry/attributes/exception/)
- [OpenTelemetry: exceptions in logs](https://opentelemetry.io/docs/specs/semconv/exceptions/exceptions-logs/)
- [Loki HTTP API](https://grafana.com/docs/loki/latest/reference/loki-http-api/)
- [CloudWatch Logs: FilterLogEvents](https://docs.aws.amazon.com/AmazonCloudWatchLogs/latest/APIReference/API_FilterLogEvents.html)
- [CloudWatch Logs: FilteredLogEvent](https://docs.aws.amazon.com/AmazonCloudWatchLogs/latest/APIReference/API_FilteredLogEvent.html)
- [CloudWatch Logs: filter pattern syntax](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/FilterAndPatternSyntax.html)

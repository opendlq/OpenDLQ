# Pesquisa: contrato comum para o Log Provider

- **Data:** 2026-11-23 (duas passadas de verificação no mesmo dia)
- **Pergunta:** que campos Sentry, Datadog, Elastic (ECS, Logstash, Kibana), OpenTelemetry, Loki, CloudWatch, Splunk, New Relic, Honeycomb e Grafana Tempo usam para guardar um erro, e dá para definir um contrato único que o OpenDLQ use para mostrar "esse erro aconteceu, com esse log e esse stack trace"?
- **Resposta curta:** dá. Os sistemas guardam o erro de três formas diferentes, então o contrato fica no menor denominador comum e cada provider traduz a sua origem. O mapeamento e as decisões abaixo são **leitura minha** da documentação oficial, não algo que os docs do projeto já definam.
- **Convenção:** o que está escrito como fato foi lido no texto da página. O que é composição ou dedução minha está marcado como **inferência**. O que não consegui confirmar está na seção 5.

Contexto no projeto: `docs/plugins.md` define o Log Provider como "Correlation IDs + time window → logs", e `docs/components/enricher.md` define o que é guardado em `enrichments.data` (limite de 16 KB, extração por JSON path).

## 1. O que cada sistema guarda

### 1.1 Os seis sistemas lidos por completo

| Canônico | Sentry (REST) | Datadog | Elastic ECS (Logstash, Kibana) | OTel | Loki / CloudWatch |
| --- | --- | --- | --- | --- | --- |
| ID | `event_id` (32 hex) | `data[].id` | `_id` do documento | n/a | CW: `eventId` |
| Hora | `timestamp` (RFC 3339 ou epoch s) | `attributes.timestamp` | `@timestamp` | `Timestamp` (uint64 ns); em OTLP/JSON, `timeUnixNano` como string | Loki: ns em string. CW: `timestamp` em ms |
| Nível | `level` (`fatal`…`debug`) | `status` | `log.level` | `SeverityText` / `SeverityNumber` (ERROR = 17–20) | só dentro da linha |
| Serviço | `server_name` / tag | `service` | `service.name` | `service.name` no Resource (string, Stable) | label do stream / `logStreamName` |
| Mensagem | `title` | `message` | `message` | `Body` | linha / `message` (string opaca) |
| Tipo do erro | `exception.values[].type` | `error.kind`, `error.type` | `error.type` | `exception.type` | só dentro da linha |
| Mensagem do erro | `exception.values[].value` | `error.message` | `error.message` | `exception.message` | só dentro da linha |
| Stack trace | `stacktrace.frames[]` estruturado, **mais antigo primeiro** | `error.stack` (string) | `error.stack_trace` (string) | `exception.stacktrace` (string) | só dentro da linha |
| Trace | `contexts.trace.trace_id` (obrigatório no trace context, 32 hex) | `trace_id` (number, reservado) | `trace.id` | `TraceId` (hex em OTLP/JSON) | só dentro da linha |

### 1.2 Os quatro sistemas adicionais

| Sistema | Tipo | Onde está o erro | Como consultar | Limites lidos |
| --- | --- | --- | --- | --- |
| Splunk | log | Nenhum campo padrão de erro confirmado | `search/v2/jobs/export` (só o caminho foi confirmado) | não confirmados |
| New Relic | log (evento `Log`) | `message` (JSON no `message` é parseado e achatado, por exemplo `user.id`), `timestamp`, `entity.name`/`entity.guid`/`entity.type` reservados. Nível, trace e `error.*` não confirmados | NerdGraph: `actor { account(id:) { nrql(query:) { results } } }`, com `SELECT … FROM Log …` | `LIMIT` máximo 5.000 (padrão 100 em `SELECT *`), 3.000 queries/min por conta, 120 repetidas/min, timeout de 5 s no NerdGraph |
| Honeycomb | log e trace | `trace.trace_id`, `trace.span_id`, `trace.parent_id`, `service.name`, `name`. Campos `exception.*` não confirmados | `POST /1/queries/{dataset}`, depois `POST /1/query_results/{dataset}` com `query_id`, depois `GET /1/query_results/{dataset}/{id}` (assíncrono, campo `complete`) | plano Enterprise, só 7 dias, 10 criações/min, 10 s por query, `limit` até 10.000 |
| Grafana Tempo | trace | evento de span `exception` com `exception.type`, `exception.message`, `exception.stacktrace` | `GET /api/v2/traces/<traceID>` (OTel JSON); `GET /api/search` com `q` (TraceQL), `start`, `end`, `limit` | `limit` padrão 20; `start`/`end` errados podem dar resultado parcial |

### 1.3 Detalhes que importam na implementação

- **Sentry.** `exception.values[]` exige `type` ou `value`. Cada frame exige `filename`, `function` ou `instruction_addr`, e tem `lineno`, `in_app`. A resposta REST usa camelCase (`lineNo`, `inApp`, `absPath`), diferente do payload do SDK (snake_case). O provider lê o REST. O trace context (`contexts.trace`) exige `trace_id` (16 bytes em hex, 32 caracteres) e `span_id`.
  - **Consulta.** `GET /api/0/organizations/{org}/events/` (Explore) aceita `dataset` (inclui `errors`), `field` (obrigatório, máximo 20), `query`, `statsPeriod`, `per_page` (máximo 100) e `cursor`. A página diz que é para tabela, "not for doing a full export".
  - **Por issue.** `GET /api/0/organizations/{org}/issues/{issue_id}/events/` aceita `query`, `full` e `per_page` (máximo 100).
  - **Busca.** A sintaxe é `chave:valor`, e a doc diz que a API usa a mesma sintaxe da busca na interface. `trace`, `event.type`, `message`, `error.type`, `error.value` e `stack.filename` são propriedades pesquisáveis de evento.
  - **Paginação e limites.** Paginação pelo header `Link` com `cursor`. Limites por chamador e endpoint, com os headers `X-Sentry-Rate-Limit-*`. A doc recomenda webhook em vez de polling.
- **Datadog.** `POST /api/v2/logs/events/search` aceita `filter.query`, `filter.from`, `filter.to`, `page.limit` e `page.cursor`. A resposta traz `data[].attributes` e `meta.page.after`. Permissão: `logs_read_data`.
  - **Atributos.** A tabela de atributos padrão lista `error.kind`, `error.source`, `error.type`, `error.message`, `error.stack` (todos string) e `error.id` (string, UUID, ligado ao RUM). `trace_id` é reservado e aparece como `number`.
  - **Injeção pelos tracers.** Variam por linguagem. Python injeta `dd.trace_id` e `dd.span_id` como inteiros decimais. Node injeta um objeto `dd` com `trace_id` em hex de 32 caracteres e `span_id` em decimal (string). Sem a integração de logs, a doc manda parsear como string e remapear com o Trace Remapper.
  - **Busca.** `@atributo:valor` para atributos customizados. Atributos reservados (`host`, `source`, `status`, `service`, `trace_id`, `message`) dispensam o `@`. Tags: `chave:valor`. Buscas por atributo diferenciam maiúsculas de minúsculas.
- **Elastic.** `error.stack_trace` é `wildcard` no mapping, mas o cliente envia uma string. No Logstash 8 todos os plugins usam ECS v8 por padrão (`ecs_compatibility`). Kibana é uma interface sobre o Elasticsearch.
  - **`_search`.** Devolve `took`, `timed_out`, `hits.total` (`value`/`relation`) e `hits.hits[]` com `_index`, `_id`, `_source`, `sort`.
  - **Paginação.** `search_after` com um tiebreaker no `sort`, e a doc oferece o PIT (point in time) para manter o estado do índice. Por padrão `from`+`size` não passa de 10.000 hits (`index.max_result_window`).
  - **Filtros.** `bool` com `filter`, `term` e `range` (`gte`/`lte` aceitam date math). A doc desaconselha `term` em campo `text` (use `match`), mas `trace.id` é `keyword`.
  - **Campos.** O `_source` no corpo aceita array (`"_source": ["a.*"]`) ou objeto com `includes`/`excludes`.
- **OTel.** É um modelo de dados, não um store, então não há API de consulta. `exception.type` ou `exception.message` é obrigatório (um dos dois). `exception.stacktrace` é string "in the natural representation for the language runtime".
  - **OTLP/JSON.** Chaves em lowerCamelCase. `traceId` e `spanId` são strings hex (não base64, sem distinção de caixa). Inteiros de 64 bits e `timeUnixNano` são strings decimais. Enums vão como inteiro (`severityNumber`). Atributos vão como `{"key": …, "value": {"stringValue": …}}`.
  - **Estrutura.** `resourceLogs[]` → `scopeLogs[]` → `logRecords[]`.
  - **Exceções em spans.** A página de exceções em spans marca o evento `exception` de span como deprecated e manda usar as convenções de exceção em logs.
- **Loki.** `GET /loki/api/v1/query_range` devolve `data.result[].stream` (labels) e `values` como pares `[ns, linha]`. `limit` padrão 100.
  - **LogQL.** `|= "texto"` e `|~ regex` filtram linhas. `| json` extrai as propriedades como labels (chaves aninhadas viram `a_b`). Filtro por campo extraído: `{job="x"} | json | trace_id="abc"` (a composição é **inferência**, as partes estão documentadas).
  - **Limites do servidor (`limits_config`).** `max_entries_limit_per_query` 5000, `max_query_length` 30d1h, `max_query_lookback` 0s (sem limite), `max_query_range` 0s (sem limite).
  - **Structured metadata.** Segundo a doc, é "added to the labels returned for the query".
- **CloudWatch.** `FilterLogEvents` devolve até 10.000 eventos ou 1 MB por página, com `nextToken` (expira em 24 h). Filtro por campo JSON: `{ $.requestId = "abc" }`. Limite de 5 a 25 TPS por região, não ajustável.

## 2. O que isso muda no contrato

1. **Três grupos.** O Sentry guarda o erro estruturado. Datadog, Elastic e OTel guardam log com campos padrão. Loki, CloudWatch e (pelo que li) New Relic guardam texto ou JSON no `message`, sem campo de erro. Para esses, o `extract` por JSON path do `enricher.md` continua necessário. Honeycomb e Tempo são stores de trace, e o erro vive em atributos de span ou em eventos de span.
2. **Stack trace é string em 3 dos 4 que têm o campo.** Só o Sentry estrutura frames, e na ordem oposta à de um trace de Java. O contrato guarda sempre a string e aceita `Frames` como opcional.
3. **Trace ID é o único ponto em comum, mas o formato varia.** ECS, OTel e Sentry usam hex de 32 caracteres. No Datadog o `trace_id` reservado é `number`, e os tracers injetam decimal (Python) ou hex de 32 (Node). O core entrega o ID em hex de 32 (do `traceparent`), e o provider do Datadog precisa saber qual formato procurar. `x-request-id` e similares dependem do nome do campo que cada time usa, então o mapeamento fica na config do Provider.
4. **O Sentry tem busca por `query`.** O Explore events (`dataset=errors`) e o endpoint de eventos por issue aceitam `query`. Como `trace` é uma propriedade pesquisável e a API usa a mesma sintaxe da interface, `query=trace:<id>` deve funcionar (**inferência**, a combinação não aparece em nenhuma página). O provider do Sentry deve preferir esse caminho e cair para tag quando não houver trace.
5. **Os limites variam, mas um `Limit` de 20 cabe em todos.** Os padrões lidos: Datadog 10, Tempo 20, Loki, New Relic e Honeycomb 100, Sentry até 100 por página, CloudWatch até 10.000. Também cabe no limite de 16 KB do `enrichments.data`.
6. **Nenhum precisa de paginação no contrato.** Com `Limit` pequeno e janela `From`/`To` curta, uma página basta. O Loki nem documenta paginação além do `limit`.

## 3. Contrato proposto

```go
type LogProvider interface {
    Query(ctx context.Context, q Query) (Result, error) // ErrNotFound → not_found
}

type Query struct {
    TraceID  string            // hex de 32 (W3C); o provider converte p/ o formato da origem
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

- **Normalização.** O provider preenche os campos canônicos. O `extract` da config do Consumer sobrescreve ou preenche o que faltar, que é o caso de Loki, CloudWatch e New Relic. Hoje o `extract` só alimenta `data`, então isso estende o que o `enricher.md` define.
- **Ordem dos frames.** Mais recente primeiro, o que casa com o `stack[0]` do `stack_top` no `enricher.md`. O provider do Sentry inverte a lista.
- **Correlação.** O core converte o `traceparent` em `TraceID` e manda os outros headers em `IDs`. O provider traduz cada um por um `correlation_fields` na spec do Provider, por exemplo `x-request-id: attributes.request_id`.
- **Formato do trace ID no Datadog.** Como os tracers injetam formatos diferentes, o Provider do Datadog precisa de uma opção para isso (por exemplo `trace_id_format: decimal | hex`). O nome e os valores são proposta minha.
- **Nível do plugin.** O `plugins.md` coloca o Log Provider no nível 3 (adapters compilados, mantidos pelo projeto). Para terceiros criarem o provider sem fork, ele precisa ir para o nível 2 (out-of-process, gRPC).
- **Quais providers vêm primeiro.** Os que têm contrato verificado de ponta a ponta: Datadog, Elasticsearch, Loki, CloudWatch e Sentry. Splunk, New Relic e Honeycomb ficam depois, e Tempo só faz sentido se o erro for lido de trace.

## 5. O que não foi verificado

- **Datadog:**
  - O máximo de `page.limit` na Search API. O guia diz "up to 1000" com padrão 50, e a referência diz padrão 10 e tem um exemplo com `limit` 5000.
  - Um exemplo de busca por `trace_id:<id>`. Só existe a regra de que atributos reservados dispensam o `@`, então a busca é **inferência**.
  - O formato de `dd.trace_id` em Java e Go (decimal ou hex), e se o pipeline remapeia para o `trace_id` reservado fora de Python e Java.
- **OTel:** o nível de requisito de `service.name`. A página não tem essa coluna. Não afeta o contrato.
- **Loki:** `encodingFlags` e `categorize-labels` não aparecem na documentação lida. A resposta documentada de `query_range` tem só pares `[ns, linha]`. Paginação além do `limit` também não é documentada, só há a orientação de chamadas repetidas na seção de `tail`.
- **Elasticsearch:**
  - `_source_includes`, `_source_excludes` e `?_source=` como parâmetros de URL não aparecem na página lida, só a forma no corpo da requisição.
  - A consulta `bool` com `term` em `trace.id` e `range` em `@timestamp` é composição minha a partir de exemplos verificados separadamente.
  - A forma de objeto de `hits.total` vem do exemplo da query `term`, não da referência do `_search`.
- **Sentry:**
  - `query=trace:<id>` no Explore events (ver seção 2, item 4).
  - Os nomes aceitos em `field` do Explore events. As propriedades pesquisáveis estão documentadas, mas não a lista de colunas retornáveis.
  - Se o `query` do endpoint de issues aceita tags (a descrição diz só "optional search query").
  - `trace.span` como propriedade, e `GET …/issues/{issue_id}/events/latest/`.
  - Se a resposta REST mantém `contexts.trace`. Ele aparece como campo obrigatório no payload do SDK e no exemplo de resposta REST lido na primeira passada.
- **Splunk:** quase tudo. `docs.splunk.com` retorna 403. No `help.splunk.com` só consegui confirmar o caminho `search/v2/jobs/export`, o header `Authorization: Splunk <hec_token>` e que o `event` aparece como string nos exemplos do HEC. As chaves do HEC (`time`, `host`, `source`, `sourcetype`, `index`, `fields`), os parâmetros do export, o formato do resultado, os limites e qualquer campo padrão de erro (CIM) **não** foram confirmados.
- **New Relic:** nível, `trace.id`, `span.id` e `error.*` em logs. As páginas de atributos nativos e de logs in context retornaram 404.
- **Honeycomb:** os campos `exception.*` e a busca por trace ID (o formato de filtro `column`/`op`/`value` está documentado, mas o uso com `trace.trace_id` não). A doc também é inconsistente no `limit` padrão (1.000 em um schema, 100 em outro).
- **Tempo:** autenticação da API e a sintaxe TraceQL para filtrar exceções.

## 6. Fontes

**Sentry**
- [Errors wire format (Exception interface)](https://develop.sentry.dev/sdk/telemetry/errors/)
- [Stacktrace interface](https://develop.sentry.dev/sdk/data-model/event-payloads/stacktrace/)
- [Event payloads](https://develop.sentry.dev/sdk/foundations/envelopes/event-payloads/)
- [Contexts (trace context)](https://develop.sentry.dev/sdk/foundations/envelopes/event-payloads/contexts/)
- [API: Retrieve an event](https://docs.sentry.io/api/events/retrieve-an-event-for-a-project/)
- [API: List an organization's issues](https://docs.sentry.io/api/events/list-an-organizations-issues/)
- [API: List an issue's events](https://docs.sentry.io/api/events/list-an-issues-events/)
- [API: Query Explore events in table format](https://docs.sentry.io/api/explore/query-explore-events-in-table-format/)
- [Search](https://docs.sentry.io/concepts/search/)
- [Searchable properties: events](https://docs.sentry.io/concepts/search/searchable-properties/events/)

**Datadog**
- [Standard attributes](https://docs.datadoghq.com/standard-attributes.md?product=log+management)
- [Search syntax](https://docs.datadoghq.com/logs/explorer/search_syntax/)
- [Connect logs and traces (Python)](https://docs.datadoghq.com/tracing/other_telemetry/connect_logs_and_traces/python/)
- [Connect logs and traces (Node.js)](https://docs.datadoghq.com/tracing/other_telemetry/connect_logs_and_traces/nodejs/)
- [Collect multiple logs with pagination](https://docs.datadoghq.com/logs/guide/collect-multiple-logs-with-pagination/)
- [API: Search logs](https://docs.datadoghq.com/api/latest/logs/search-logs-post.md)

**Elastic**
- [ECS: error](https://www.elastic.co/guide/en/ecs/current/ecs-error.html)
- [ECS: log](https://www.elastic.co/guide/en/ecs/current/ecs-log.html)
- [ECS: tracing](https://www.elastic.co/guide/en/ecs/current/ecs-tracing.html)
- [Logstash: ECS compatibility](https://www.elastic.co/guide/en/logstash/current/ecs-ls.html)
- [Elasticsearch: Paginate search results](https://www.elastic.co/guide/en/elasticsearch/reference/current/paginate-search-results.html)
- [Elasticsearch: term query](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-term-query.html)
- [Elasticsearch: range query](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-range-query.html)
- [Elasticsearch: bool query](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-bool-query.html)
- [Elasticsearch: retrieve selected fields](https://www.elastic.co/guide/en/elasticsearch/reference/current/search-fields.html)

**OpenTelemetry**
- [Logs data model](https://opentelemetry.io/docs/specs/otel/logs/data-model/)
- [Exception attributes](https://opentelemetry.io/docs/specs/semconv/registry/attributes/exception/)
- [Exceptions in logs](https://opentelemetry.io/docs/specs/semconv/exceptions/exceptions-logs/)
- [Exceptions in spans](https://opentelemetry.io/docs/specs/semconv/exceptions/exceptions-spans/)
- [Service attributes](https://opentelemetry.io/docs/specs/semconv/registry/attributes/service/)
- [OTLP (JSON Protobuf encoding)](https://opentelemetry.io/docs/specs/otlp/)
- [logs.proto](https://github.com/open-telemetry/opentelemetry-proto/blob/main/opentelemetry/proto/logs/v1/logs.proto)
- [Exemplo logs.json](https://github.com/open-telemetry/opentelemetry-proto/blob/main/examples/logs.json)

**Loki**
- [HTTP API](https://grafana.com/docs/loki/latest/reference/loki-http-api/)
- [Log queries (LogQL)](https://grafana.com/docs/loki/latest/query/log_queries/)
- [Structured metadata](https://grafana.com/docs/loki/latest/get-started/labels/structured-metadata/)
- [Configuração (`limits_config`)](https://github.com/grafana/loki/blob/main/docs/sources/shared/configuration.md)

**CloudWatch Logs**
- [FilterLogEvents](https://docs.aws.amazon.com/AmazonCloudWatchLogs/latest/APIReference/API_FilterLogEvents.html)
- [FilteredLogEvent](https://docs.aws.amazon.com/AmazonCloudWatchLogs/latest/APIReference/API_FilteredLogEvent.html)
- [Filter pattern syntax](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/FilterAndPatternSyntax.html)

**New Relic**
- [Log API](https://docs.newrelic.com/docs/logs/log-api/introduction-log-api/)
- [Parsing de logs](https://docs.newrelic.com/docs/logs/ui-data/parsing/)
- [NerdGraph NRQL tutorial](https://docs.newrelic.com/docs/apis/nerdgraph/examples/nerdgraph-nrql-tutorial/)
- [NRQL: LIMIT](https://docs.newrelic.com/docs/nrql/nrql-syntax-clauses-functions/)
- [Limites de queries NRQL](https://docs.newrelic.com/docs/query-your-data/nrql-new-relic-query-language/get-started/rate-limits-nrql-queries/)

**Honeycomb**
- [API: Queries](https://docs.honeycomb.io/api/queries/)
- [API: Create a query result](https://docs.honeycomb.io/api/query-data/create-a-query-result.md)
- [API: Get query result](https://docs.honeycomb.io/api/query-data/get-query-result.md)
- [OpenTelemetry](https://docs.honeycomb.io/send-data/opentelemetry/)

**Grafana Tempo**
- [HTTP API](https://grafana.com/docs/tempo/latest/api_docs/)

**Splunk**
- [Format events for HTTP Event Collector](https://help.splunk.com/en/splunk-enterprise/get-data-in/get-started-with-getting-data-in/10.6/get-data-with-http-event-collector/format-events-for-http-event-collector)
- [REST API: search endpoints](https://help.splunk.com/en/splunk-enterprise/rest-api-reference/10.6/search-endpoints)

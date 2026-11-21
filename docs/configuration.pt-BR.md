# Configuração

[English](configuration.md)

Toda a configuração do OpenDLQ é um conjunto de recursos declarativos, no estilo do Kubernetes: um documento YAML por recurso, com `kind`, `metadata` e `spec`.

## Recursos

| Kind | O que declara |
| --- | --- |
| `Consumer` | Um consumer: a DLQ de origem, o tópico original, o serializador, os headers de correlação |
| `Policy` | Retry, circuit breaker, sonda, detecção de recuperação e TTL de um consumer |
| `Classifier` | Regras de classificação, ou o plugin classificador a usar |
| `Runbook` | O tratamento de uma falha persistente conhecida. Veja [runbooks](runbooks.pt-BR.md) |
| `Alert` | Uma condição de alerta e para onde ela vai. Veja [alertas](alerts.pt-BR.md) |

```yaml
kind: Consumer
metadata:
  name: order-events
spec:
  source: { plugin: kafka, topic: order-events.dlq }
  replay_to: { plugin: kafka, topic: order-events }
  serde: json
  correlation_headers: [traceparent, x-request-id]
---
kind: Classifier
metadata:
  name: order-events-rules
  consumer: order-events
spec:
  transient: [timeout, 5xx, 429, connection_refused, deadlock]
  permanent: [4xx, parse_error, validation, nil_dereference]
```

## Dois jeitos de operar, um só efeito

- **Declarativo.** Os arquivos ficam num repositório. Mudanças passam por pull request e revisão.
- **Interativo.** API, CLI e UI, para ações pontuais e exploração.

```sh
opendlq diff   -f ./config/   # declarado vs. aplicado
opendlq apply  -f ./config/   # aplica o estado declarado
opendlq export <kind>/<name>  # grava o estado aplicado de volta num arquivo
```

## Drift

Quando um recurso está declarado em arquivo, o arquivo é a fonte de verdade. Uma mudança feita pela API ou pela UI num recurso declarado fica registrada como **drift** e aparece em `opendlq diff`. O operador escolhe:

- `opendlq export` para levar a mudança para o arquivo, ou
- `opendlq apply` para restaurar o arquivo e descartar a mudança.

Ações pontuais (reprocessar, descartar, reclassificar, aprovar uma execução de runbook) não são recursos e não geram drift.

## Agentes

Agentes de IA usam o mesmo caminho que pessoas: editam o YAML, rodam `opendlq diff`, abrem pull request. As mudanças passam pela mesma revisão. Não existe API privilegiada.

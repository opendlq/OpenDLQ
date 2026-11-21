# Alertas

[English](alerts.md)

Alertas são declarados, não configurados numa UI. Cada alerta é um recurso `Alert` no repositório de configuração.

```yaml
kind: Alert
metadata:
  name: order-events-stuck
  consumer: order-events
spec:
  when: max_age > 2h
  severity: page
  notify: [pagerduty:payments-oncall]
---
kind: Alert
metadata:
  name: recurring-causes
spec:
  when: recurrence.episodes >= 3 and recurrence.cost_trend == "growing"
  severity: report
  notify: [slack:#eng-priorities]
  schedule: weekly
```

## Dois públicos

O OpenDLQ separa os alertas por quem deve agir:

| Tipo | Para | Exemplos |
| --- | --- | --- |
| **Operacional** | Quem está de plantão | Retries esgotados, novo grupo persistente, circuito aberto por muito tempo, idade máxima acima do limite |
| **Decisão** | Quem define prioridades | Uma causa que continua voltando, custo crescendo, runbook perto de expirar |

Um alerta operacional diz "aja agora". Um alerta de decisão diz "isso continua custando caro, corrija a causa raiz". Misturar os dois ensina as pessoas a ignorar ambos.

## Condições

Uma condição de alerta é uma expressão sobre eventos e métricas:

| Fonte | Exemplos |
| --- | --- |
| Eventos | `exhausted`, `poisoned` (nova mensagem esperando operador), `circuit_opened`, `runbook_step`, `runbook_expiring` |
| Métricas | `max_age`, `open_count`, `self_recovery_rate`, `time_to_triage` |
| Reincidência | `recurrence.episodes`, `recurrence.cost_trend` |

## Contexto em toda notificação

Um alerta que dispara sem contexto faz a investigação começar do zero. Toda notificação leva:

- A causa e sua chave de agrupamento.
- Quantas mensagens, desde quando e a tendência.
- Um exemplo de payload e erro.
- O trecho do log correlacionado, quando houver.
- Links: o grupo no OpenDLQ, os logs, o trace.
- O runbook que casa, se existir.

## Quem envia notificações

Só o Alerts Watcher. Os outros componentes emitem eventos e nunca notificam diretamente. Assim toda regra de alerta fica num só lugar, declarada e revisada.

Os canais de notificação são plugins: Slack, PagerDuty, Opsgenie, webhook.

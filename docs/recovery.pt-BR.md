# Recuperação

[English](recovery.md)

O OpenDLQ recupera falhas transientes sem envolvimento humano. Quatro mecanismos trabalham juntos. Todos são definidos por consumer num recurso `Policy`.

```yaml
kind: Policy
metadata:
  name: order-events-default
  consumer: order-events
spec:
  retry:   { max: 5, base: 30s, factor: 2, cap: 30m, jitter: 0.2 }
  breaker: { window: 60s, threshold: 20, canary_every: 30s, canary_cap: 5m, drain_rate: 50 }
  recovery: { mode: ack, topic: opendlq.ack, timeout: 10s }
  ttl: 72h
```

## Retry com backoff exponencial e jitter

Padrão: 5 tentativas, base 30 s, fator 2, teto 30 min, jitter de ±20%.

O jitter evita que mensagens que falharam juntas voltem juntas. Quando as tentativas acabam, a mensagem é tratada como persistente e espera um operador.

## Circuit breaker por dependência

A chave do breaker é o `x-failure-dependency`, quando o consumer envia, ou o nome do consumer, quando não envia.

O breaker abre quando 20 ou mais mensagens distintas falham com o mesmo erro ou a mesma dependência em 60 s. Enquanto ele está aberto:

- Nenhuma mensagem daquela chave é retentada. As mensagens ficam **seguradas**.
- O tempo segurado não conta como tentativa.

Só falhas classificadas como transientes contam para abrir o breaker. Vinte mensagens com o mesmo erro de validação não parecem uma dependência indisponível.

## Sonda

Com o breaker aberto, uma sonda verifica se a dependência voltou. A sonda é um plugin:

- **Canário (padrão):** a cada 30 s, reenvia uma mensagem segurada, a mais antiga. O intervalo dobra a cada falha, até 5 min.
- **Health check:** chama um endpoint HTTP da dependência. Útil quando reenviar uma mensagem real não é seguro.

Quando a sonda passa, o breaker fecha.

## Drenagem controlada

Depois que o breaker fecha, o backlog segurado drena em ordem de chegada, com vazão configurável (padrão 50 msg/s). O limite evita que uma dependência que acabou de voltar caia de novo com o backlog.

Mensagens com a mesma chave de partição são reenviadas na ordem original.

## Detecção de recuperação

Um replay não é recuperação até o consumer confirmar. Dois modos, definidos por consumer:

| Modo | Como funciona | Trade-off |
| --- | --- | --- |
| `ack` | O consumer publica o `x-dlq-id` em `opendlq.ack` depois de processar. Sem ack dentro do prazo, conta como falha. | Preciso. Exige uma pequena mudança no consumer. |
| `silence` | A mensagem conta como recuperada se não voltar à DLQ em N segundos. | Nenhuma mudança no consumer. Pode contar uma falha lenta como sucesso. |

## Idempotência

Todo replay leva `x-dlq-id` e `x-dlq-attempt`. O contrato com o consumer: se ele já processou esse `x-dlq-id` com sucesso, ignora e confirma.

O OpenDLQ não garante idempotência sozinho. Ele garante que o consumer tem a informação para ser idempotente. Um replay sem esse contrato não é seguro.

## O que uma política nunca faz

- Retentar uma falha persistente sem operador ou runbook.
- Alterar um payload sem operador ou runbook.
- Reenviar fora da chave de partição original.

## Por que retries curtos ficam no consumer

Um retry de poucos segundos é responsabilidade do consumer. O OpenDLQ trata o que sobreviveu a ele: uma indisponibilidade de minutos ou horas, em que o consumer não consegue segurar a mensagem sem travar a partição. Hoje essa mensagem vira problema humano, embora a solução seja esperar. É para esse caso que a recuperação existe.

# Analytics

[English](analytics.md)

O OpenDLQ mede o que acontece com as mensagens que falharam, para o time de engenharia ver o que corrigir. O analytics só lê o state store e o log de auditoria. Nenhuma métrica depende do conteúdo da mensagem.

O analytics tem consistência eventual, com atraso máximo declarado. Estado, replay e auditoria não.

## Métricas base

Por consumer, causa, dependência e dia:

- Mensagens que entraram. Mensagens que saíram, por destino.
- Idade das mensagens abertas: média, p95, máxima. **A idade máxima é o alerta principal.** A profundidade da fila esconde mensagens antigas no fundo.
- Taxa de auto-recuperação: a fração de mensagens que saiu sem ação humana. É a métrica do caminho transiente.
- Tempo até triagem para falhas persistentes: da chegada até a primeira ação de um operador.
- Tentativas por mensagem recuperada.
- Tempo com o circuito aberto, por dependência.

## Funil de resolução

Para cada período e cada corte (consumer, causa, dependência), onde cada mensagem terminou:

| Resultado | Significado |
| --- | --- |
| Recuperada sozinha | Caminho transiente, sem pessoa envolvida |
| Reprocessada por operador | Persistente, corrigida por uma pessoa |
| Tratada por runbook | Persistente, corrigida por uma decisão declarada |
| Roteada | Enviada para outro destino |
| Descartada | Removida com motivo |
| Expirada | TTL atingido |
| Ainda aberta | Esperando |

Cada resultado vem com a distribuição do tempo até chegar lá. O funil responde três perguntas: o que resolvemos sozinhos, o que exige gente e o que está parado.

## Custo

Cada mensagem acumula custo em três partes:

| Parte | Cálculo |
| --- | --- |
| Armazenamento | Bytes × tempo no state store |
| Replay | Tentativas × custo unitário configurável |
| Operador | Minutos de ação humana no log de auditoria × custo-hora configurável |

Somado por causa e por consumer, o custo responde duas perguntas: quanto uma causa custou no período e qual consumer é a maior fatia. A tendência do custo é o argumento para corrigir o upstream em vez de reprocessar para sempre.

## Reincidência

Uma reincidência é a mesma causa voltando depois de tratada. O OpenDLQ detecta três formas:

1. **Mesma mensagem.** Reprocessada e de volta à DLQ com o mesmo `x-dlq-id`. A correção não funcionou, ou o problema é outro.
2. **Mesma causa, mensagens novas.** Uma chave de agrupamento volta depois de um período sem ocorrências. A causa raiz nunca foi corrigida.
3. **Mesma dependência.** O circuit breaker de uma dependência abre várias vezes. A dependência é instável.

Para cada causa, o OpenDLQ guarda:

- Primeira e última ocorrência.
- Número de episódios. Um episódio é uma janela de ocorrências, separada da próxima por um período de silêncio configurável.
- Mensagens por episódio.
- Custo acumulado.
- Tendência: crescendo, estável, caindo.

Uma causa com três ou mais episódios e custo crescente gera um alerta de reincidência. Veja [alertas](alerts.pt-BR.md).

## Exportação

A instrumentação usa OpenTelemetry:

- Métricas e traces saem via OTLP para qualquer backend compatível.
- As mesmas métricas também saem num endpoint Prometheus, `/metrics`, para times que fazem scrape.
- Um replay continua o trace original quando a mensagem traz `traceparent`. A cadeia completa aparece na sua ferramenta de tracing: falha original, DLQ, replay, sucesso.

Consultas detalhadas (funil, custo, reincidência) ficam em `/analytics`. Dashboards ficam nas ferramentas que o time já usa, não no OpenDLQ.

## Armazenamento

Na V0, o analytics é SQL sobre o state store, com rollups por hora e por dia. Quando o volume crescer, a tabela `transitions` vai para um banco colunar via change data capture. O lado transacional não muda.

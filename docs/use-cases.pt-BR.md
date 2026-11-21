# Casos de uso

[English](use-cases.md)

O núcleo é o mesmo em todos os casos. O que muda é a proporção entre falhas transientes e persistentes, e portanto qual metade do OpenDLQ trabalha mais.

| Caso | Proporção estimada | O que falha | O que mais importa |
| --- | --- | --- | --- |
| Webhooks de terceiros | Maioria transiente | Timeout, 503, rate limit no destino | Circuit breaker por destino, sonda, retry longo |
| Notificações (push, e-mail, SMS) | Maioria transiente | Provedor instável, quota | Retry com TTL: depois de X horas a mensagem perde o sentido e expira |
| Eventos de e-commerce | Mista | Serviço de estoque fora (transiente); SKU inexistente (persistente) | Os dois caminhos; o agrupamento por causa separa os dois |
| Ingestão de dados / ETL | Maioria persistente | Registro malformado, mudança de schema | Agrupamento, edição de payload em lote, replay com transformação |
| Migração entre sistemas | Persistente, temporária | O sistema novo ainda não reconhece o evento | Um runbook `quiet` segura as mensagens sem alertar; o operador libera o lote depois |
| Processamento financeiro em lote | Mista; idempotência crítica | Duplicidade é pior que atraso | Detecção de recuperação por ack, drenagem lenta, log de auditoria |

As proporções são estimativas, não medições.

# Runbooks

[English](runbooks.md)

Um runbook diz ao OpenDLQ o que fazer com uma falha persistente conhecida. O operador escreve. O OpenDLQ executa, dentro de limites.

Sem runbook, uma falha persistente sempre espera uma pessoa. Com runbook, o operador toma essa decisão antes.

```yaml
kind: Runbook
metadata:
  name: legacy-sku-format
  consumer: order-events
spec:
  match:
    reason: "validation: sku format"
    group_key: "sku-format-v1"
  action:
    transform: ./transforms/sku-v1-to-v2.jsonata
    replay: original
  guardrails:
    max_per_hour: 500
    approval_required_first: 3
    expires: 2027-03-01
```

## Match

Um runbook casa por qualquer combinação de consumer, motivo, chave de agrupamento, dependência ou uma expressão sobre headers e payload (CEL). Os runbooks são avaliados antes do caminho transiente: um runbook também pode cobrir um caso transiente conhecido.

## Ações

| Ação | Efeito |
| --- | --- |
| `transform` + `replay` | Altera o payload e reenvia |
| `replay` | Reenvia sem alterar |
| `route` | Envia a mensagem para outro tópico ou endpoint |
| `discard` | Descarta com motivo registrado |
| `quiet` | Mantém a mensagem esperando operador, sem notificações |
| `notify` | Envia uma notificação com contexto, sem outra mudança |

Ações customizadas são plugins.

## Guardrails

Todo runbook precisa declarar:

- **Limite de vazão:** sobre quantas mensagens por hora ele pode agir.
- **Aprovação:** quantas primeiras execuções precisam de aprovação de um operador antes de ele rodar sozinho.
- **Data de expiração:** um runbook sem ela é rejeitado.

A expiração é proposital. Um runbook é um paliativo documentado, não uma correção definitiva. Quando ele expira, as falhas voltam a esperar um operador, e a causa raiz volta a aparecer. O [analytics de reincidência](analytics.pt-BR.md#reincidência) mostra há quanto tempo um paliativo cobre um problema.

## Ciclo de vida

1. **Sugestão.** Quando um operador aplica a mesma ação ao mesmo grupo três vezes, o OpenDLQ sugere um runbook com esse match e essa ação.
2. **Dry run.** O operador roda o runbook contra o histórico de mensagens no state store e vê o que ele teria feito.
3. **Aprovação.** O runbook entra no repositório de configuração por pull request, como qualquer recurso.
4. **Execuções supervisionadas.** As primeiras N execuções esperam aprovação.
5. **Execuções automáticas.** Depois disso, o runbook roda sozinho, dentro do limite de vazão.
6. **Expiração.** O runbook para. O operador renova ou corrige a causa raiz.

Toda execução fica no log de auditoria com o nome e a versão do runbook.

## O que continua valendo

Falhas persistentes continuam nunca sendo retentadas sozinhas. A única diferença é que uma pessoa declarou a decisão antes, com limites, num arquivo que passou por revisão.

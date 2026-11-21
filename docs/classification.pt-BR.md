# Classificação

[English](classification.md)

Toda mensagem que chega ao OpenDLQ recebe um de dois tipos. O tipo decide o que acontece em seguida.

| | Transiente | Persistente |
| --- | --- | --- |
| Causa | O ambiente: dependência, rede, lock, quota | A mensagem ou o código: schema, regra de negócio, bug |
| Retry resolve? | Sim, com tempo | Não |
| Exemplos | Timeout, `connection refused`, 503, 429, deadlock | Erro de parse, campo obrigatório ausente, 4xx de validação, `nil dereference` |
| Tratamento | Retry com backoff, circuit breaker | Agrupar, mostrar contexto, esperar decisão |
| Envolvimento humano | Só quando os retries se esgotam | Sempre, a não ser que um runbook cubra o caso |
| Métrica de sucesso | Tempo até recuperação | Tempo até triagem |

Tratar os dois tipos do mesmo jeito causa um de dois erros. Retentar tudo sobrecarrega uma dependência indisponível com mensagens que nunca vão passar. Não retentar nada aciona uma pessoa por causa de um timeout de 30 segundos.

## Como uma mensagem é classificada

O classificador consulta três sinais, em ordem, e para no primeiro que responde.

1. **Header do consumer.** O consumer publica na DLQ com os headers do [contrato de headers](#contrato-de-headers). É o caminho recomendado. É o sinal mais barato e mais preciso.
2. **Regra por tipo de erro.** Regras na configuração mapeiam uma exceção ou status para um tipo. Padrão: 5xx, timeout, `connection refused`, `ECONNRESET`, 429 e deadlock são transientes; 4xx de validação, erros de parse ou serialização, violação de constraint e `nil dereference` são persistentes. As regras são por consumer e sobrescrevem o padrão.
3. **Inferência pelo comportamento.** Sem header e sem regra, a mensagem começa como transiente. O OpenDLQ observa dois padrões:
    - **A mesma mensagem falha N vezes com o mesmo erro.** O problema é a mensagem. Ela é tratada como persistente.
    - **Muitas mensagens diferentes falham na mesma janela com o mesmo erro ou a mesma dependência.** O problema é a dependência, não as mensagens. O circuit breaker dessa dependência abre e as mensagens ficam seguradas até uma sonda passar. Veja [recuperação](recovery.pt-BR.md).

O segundo padrão detecta uma dependência indisponível sem health check externo.

## A classificação nunca é final

Um operador pode reclassificar qualquer mensagem. A reclassificação fica registrada e pode alimentar as regras do consumer. Reclassificar uma mensagem persistente como transiente é o único jeito de ela voltar a ser retentada.

## A classificação é um plugin

O núcleo define a interface:

- **Entrada:** mensagem, headers, erro.
- **Saída:** tipo (`transient` ou `permanent`), dependência, chave de agrupamento.

Os três sinais acima formam o classificador padrão. Um time troca o padrão por um plugin próprio quando o domínio pede, por exemplo quando um campo do payload identifica a causa. Nada mais no sistema muda.

## Contrato de headers

Consumers que publicam na DLQ com estes headers recebem a classificação mais precisa.

| Header | Valor | Obrigatório |
| --- | --- | --- |
| `x-failure-kind` | `transient` ou `permanent` | Recomendado |
| `x-failure-reason` | Descrição curta do erro, estável entre ocorrências | Recomendado |
| `x-failure-dependency` | Nome da dependência envolvida | Quando houver |
| `x-attempt` | Número da tentativa no consumer | Opcional |

`x-failure-reason` também é a chave de agrupamento padrão. Mantenha estável: `validation: sku format`, não a mensagem de erro completa com ids dentro.

O OpenDLQ acrescenta dois headers a todo replay:

| Header | Significado |
| --- | --- |
| `x-dlq-id` | Identidade da mensagem no OpenDLQ. Não muda entre replays. |
| `x-dlq-attempt` | Número da tentativa de replay |

Um consumer que já processou um `x-dlq-id` com sucesso deve ignorar a mensagem e confirmar o recebimento. Uma mensagem que falha de novo depois de um replay volta à DLQ com o mesmo `x-dlq-id`, e o OpenDLQ anexa a nova falha ao registro existente.

O OpenDLQ também lê headers de correlação quando existem: `traceparent`, `x-request-id`, `x-message-id` e outros nomes definidos na configuração. Veja [operação](operations.pt-BR.md#logs-correlacionados).

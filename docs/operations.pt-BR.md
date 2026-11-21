# Operação

[English](operations.md)

O que um operador pode fazer com mensagens que falharam, e por quais interfaces.

## Interfaces

| Interface | Para |
| --- | --- |
| **CLI** (`opendlq`) | Configuração (`diff`, `apply`, `export`) e ações do dia a dia |
| **API** | Integrações e a UI |
| **Servidor MCP** | Agentes de IA. As mesmas operações da CLI e da API |
| **UI** | Explorar grupos, ler contexto, agir em lote. Fora da V0 |

Todas as interfaces expõem as mesmas operações e gravam no mesmo log de auditoria.

## Ações

| Ação | Escopo | Efeito |
| --- | --- | --- |
| **Listar por causa** | Consumer, causa, dependência, período | Grupos de mensagens com contagem, idade e tendência |
| **Inspecionar** | Uma mensagem ou grupo | Payload, headers, erro, tentativas, logs correlacionados, link do trace |
| **Reclassificar** | Uma mensagem ou grupo | Muda o tipo. De persistente para transiente, as mensagens voltam a ser retentadas |
| **Reprocessar** | Uma mensagem ou lote | Envia ao tópico original ou a outro destino, com chave de idempotência, na ordem da partição |
| **Editar e reprocessar** | Uma mensagem ou lote | Altera o payload e reenvia |
| **Descartar** | Uma mensagem ou lote | Encerra com motivo registrado |
| **Aprovar** | Uma execução de runbook | Libera uma execução supervisionada de runbook |

Ações em lote recebem um filtro (consumer, chave de agrupamento, janela de tempo) e um limite de vazão.

## Logs correlacionados

Quando um consumer envia uma mensagem para a DLQ, em geral também grava um log de erro com ids de correlação: trace id, span id, id da mensagem, request id. Esse log tem contexto que a DLQ não tem: stack trace, estado do consumer, chamadas feitas antes da falha.

- O Collector extrai os ids de correlação dos headers e os grava.
- Um plugin de **provedor de logs** recebe os ids e uma janela de tempo e devolve os logs correspondentes. Provedores previstos: Elasticsearch/OpenSearch, Loki, CloudWatch Logs, Datadog Logs.
- Os logs são buscados de forma assíncrona, com retry, porque o log pode ainda não estar indexado quando a mensagem chega. Uma indisponibilidade do backend de logs nunca bloqueia a ingestão.
- O OpenDLQ guarda um link para a consulta e um trecho curto. Ele não copia logs.
- Quando o backend de logs não tem acesso por API, o OpenDLQ ainda monta um link direto a partir de um template de URL: Grafana Explore, Kibana Discover, Datadog Log Explorer.

## Log de auditoria

Toda mudança de estado é registrada na mesma transação da própria mudança: quem (pessoa, agente, runbook ou controller), o quê, quando e o resultado. O log de auditoria nunca é apagado.

## Purge

Mensagens que falharam não ficam para sempre. As regras de purge ficam na `Policy`:

- **TTL** por consumer ou por causa. Uma mensagem expirada é encerrada como `expired`, de qualquer estado aberto.
- **Arquivamento** do payload em storage frio antes de apagar.
- **Descarte automático** para causas marcadas como conhecidas e aceitas.

O purge apaga só payloads. O log de auditoria e as métricas agregadas ficam.

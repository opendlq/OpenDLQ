# Princípios de design

[English](principles.md)

Estes princípios decidem trade-offs. Quando dois desenhos funcionam, escolha o que respeita os princípios.

## 1. Nenhuma mensagem se perde. Nenhuma decisão é aplicada duas vezes.

**O que significa.** Toda mensagem lida da DLQ é gravada antes do commit do offset. Toda transição de estado é atômica, registrada e aplicada no máximo uma vez. Todo replay é enviado uma vez por decisão.

**Por quê.** A DLQ já é o lugar onde os dados deram errado. Uma ferramenta que perde ou duplica mensagens ali piora o problema e perde a confiança do time.

**Consequências.**
- O state store precisa ter transação, compare-and-set e lock de linha.
- A publicação passa por um transactional outbox, nunca direto de uma decisão.
- O analytics pode ter atraso. Estado, replay e auditoria não podem.
- O OpenDLQ não impede que o consumer receba uma duplicata. Ele envia uma chave de idempotência para o consumer deduplicar.

## 2. Humanos decidem falhas persistentes.

**O que significa.** Uma falha transiente é recuperada automaticamente. Uma falha persistente nunca é, a não ser que um operador tenha declarado antes, em um runbook, o que fazer com ela.

**Por quê.** Uma falha persistente significa que a mensagem ou o código está errado. Retentar só gera carga. Alterar a mensagem sem uma decisão pode corromper dados.

**Consequências.**
- Não existe transição automática de persistente de volta para retentando.
- Runbooks exigem guardrails: limite de vazão, aprovação nas primeiras execuções, data de expiração.
- Um runbook é um paliativo documentado, não uma correção definitiva. O analytics de reincidência mostra quando a causa raiz ainda precisa ser corrigida.

## 3. Declarativo primeiro.

**O que significa.** Políticas, classificadores, runbooks e alertas são recursos YAML. Ficam num repositório, passam por revisão e são aplicados com `opendlq apply`. A API e a UI podem alterar os mesmos recursos, mas o arquivo é a fonte de verdade. Uma mudança feita fora do arquivo aparece como drift.

**Por quê.** Configuração que só existe numa UI não pode ser revisada, versionada nem reproduzida. Numa organização grande, é assim que a configuração de DLQ vira responsabilidade de ninguém.

**Consequências.**
- `opendlq diff` mostra a diferença entre o declarado e o aplicado antes de qualquer mudança.
- Ações pontuais (reprocessar, descartar, reclassificar) não são recursos e não geram drift.

## 4. Plugável nas bordas, fixo no núcleo.

**O que significa.** Tudo que toca o mundo externo ou depende do domínio é plugin: sources, sinks, serializadores, classificadores, transformadores, sondas, provedores de log, notificadores, ações de runbook, o state store. O núcleo não é plugável: a máquina de estados, o modelo de recursos, o log de auditoria, o contrato de headers e os cálculos de analytics.

**Por quê.** Um time precisa adaptar o OpenDLQ ao seu broker e ao seu domínio. Dois times ainda precisam conseguir comparar números e compartilhar runbooks. Se o núcleo fosse plugável, cada instalação falaria uma língua diferente.

**Consequências.**
- As interfaces de plugin são públicas e versionadas.
- Mudar o núcleo é fork, não plugin.

## 5. Sobre o seu broker, nunca no lugar dele.

**O que significa.** O OpenDLQ lê da DLQ que o time já tem e escreve de volta nos tópicos que ele já usa. Ele não guarda mensagens em trânsito, não roteia tráfego e não exige um broker novo.

**Por quê.** Nenhum time vai migrar sua mensageria para adotar uma ferramenta de DLQ. Uma ferramenta que fica ao lado do sistema existente pode ser adotada um consumer por vez e removida sem migração.

**Consequências.**
- Retries curtos ficam no consumer. O OpenDLQ trata o que sobreviveu a eles.
- O suporte a cada broker vem de plugins de source e sink.

## 6. Um só caminho para humanos e agentes.

**O que significa.** Agentes de IA operam o OpenDLQ como pessoas: editam YAML, rodam `opendlq diff`, abrem pull request. A CLI, a API e o servidor MCP expõem as mesmas operações, com a mesma trilha de auditoria.

**Por quê.** Um agente com um caminho privilegiado é uma mudança que ninguém revisou. Usar o mesmo caminho mantém toda mudança visível e reversível, seja de quem for.

**Consequências.**
- Não existe endpoint exclusivo para agentes.
- Toda ação registra quem a fez, pessoa ou agente.

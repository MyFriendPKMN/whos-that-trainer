# Roadmap: Who's That Trainer? — Campaign Platform

## Visão Geral

O mod atualmente permite substituir os sprites do jogador, rival e seguidor por personagens customizados. O objetivo desta iniciativa é evoluir o mod para um sistema totalmente data-driven que permita a qualquer criador montar campanhas customizadas usando apenas JSON e imagens, sem escrever Lua.

Inspirado no conceito modular do M.U.G.E.N., o sistema evolui em quatro fases progressivas.

---

## Fase 1 — Mapeamento de Treinadores Principais (Sprite Override)

**User Story:** Como criador, quero definir em um arquivo JSON quais treinadores vanilla serão substituídos visualmente por Custom Characters, tanto no overworld quanto nas batalhas.

### O que já existe no engine

- `mod.content.sprites:register(id, def)` — registra sprite sheets de personagens.
- Hook `player.sprite(next, path, ctx)` — já usado em `character_swap.lua` para substituir o sprite de back/front do jogador.
- `npc.def.sprite` — campo em cada NPC do overworld que aponta para um `SPRITE_*` id. Já usado em `rival_swap.lua` para substituir NPCs cujo `npc.def.sprite == "SPRITE_BLUE"`.
- `mod.content.trainers:patch(oppClass, fields)` — permite alterar campos do registro de treinador, incluindo `pic` (portrait na batalha) e `paletteSource`.
- `battle.started` — evento emitido ao iniciar uma batalha com `ev.battle.kind`, `ev.battle.oppClass`.

### O que precisa ser implementado

1. **`trainer_map.json`** — arquivo JSON na raiz do mod com regras de mapeamento:
   ```json
   {
     "SPRITE_BROCK": "CUSTOM_MYCHAR",
     "OPP_BROCK": "CUSTOM_MYCHAR"
   }
   ```
   A chave `SPRITE_*` controla substituição de NPC no overworld (via `npc.def.sprite`).
   A chave `OPP_*` controla o portrait na batalha (via `mod.content.trainers:patch`).

2. **`TrainerMap` loader** — lê o JSON no `game.ready`, valida que os IDs existem em `AVAILABLE_ID` e em `data.trainers`, aplica patches via `mod.content.trainers:patch` para o `pic` e `paletteSource`.

3. **Hook `map.entered`** — itera `ow.npcs` e substitui `npc.sprite` para NPCs cujo `npc.def.sprite` bate com uma chave mapeada, reutilizando a lógica de `_applyRivalNPCSprites` de `rival_swap.lua`.

### Limitação conhecida

~~O engine não tem um hook `trainer.pic`~~. **Esta limitação não existe.** O engine já suporta paleta correta para trainer portraits via `pic` e `paletteSource` no registro `mod.content.trainers`. `BattleState.newTrainer` chama `getImage(trainerPicPath, trainerPalette)` onde `trainerPalette` lê `trainer.paletteSource` — o mesmo pipeline de paleta dos sprites de overworld. A fase 1 usa `mod.content.trainers:patch(oppClass, { pic = path, paletteSource = "SPRITE_X" })` e o portrait aparece com paleta correta automaticamente.

O bug de grayscale que existia em `rival_swap.lua` foi corrigido: o código anterior usava `love.graphics.newImage` direto no evento `battle.started` (pós-construção do battle), que não passa pelo pipeline de paleta. O fix correto — e já aplicado — é patchar o registro do treinador antes da batalha ser construída.

---

## Fase 2 — Parties Personalizadas por Treinador

**User Story:** Como criador, quero declarar no JSON de mapeamento uma equipe de até 6 Pokémon para cada treinador substituído, controlando espécie e nível.

### O que já existe no engine

- Hook `trainer.party` — existe em `BattleState.newTrainer` (linha ~670):
  ```lua
  if Runtime.wantsHook("trainer.party") then
    partyDef = Runtime.call("trainer.party", function(_, _, party)
      return party
    end, oppClass, partyIndex, partyDef) or partyDef
  end
  ```
  O hook recebe `(oppClass, partyIndex, partyDef)` e retorna o `partyDef` substituído. Cada entrada de `partyDef` é `{ species = "CHARMANDER", level = 14 }`.

- `mod.content.trainers:patch(oppClass, { parties = {...} })` — permite sobrescrever o array de parties no registro do treinador antes da batalha começar.

### O que precisa ser implementado

1. **Extensão do `trainer_map.json`**:
   ```json
   {
     "OPP_BROCK": {
       "character": "CUSTOM_MYCHAR",
       "party": [
         { "species": "GEODUDE", "level": 12 },
         { "species": "ONIX",    "level": 14 }
       ]
     }
   }
   ```

2. **`TrainerMap` loader** — ao aplicar cada mapeamento com `party` definida, chamar `mod.content.trainers:patch(oppClass, { parties = { party } })`. O índice do party é sempre 1 para treinadores mapeados (batalha única).

3. **Validação** — checar que cada `species` existe em `data.pokemon` e que `level` está em `1..100`. Emitir `mod.log:warn` para entradas inválidas e ignorá-las, nunca crashar.

---

## Fase 3 — Movesets Customizados por Pokémon

**User Story:** Como criador, quero definir os golpes de cada Pokémon da party diretamente no JSON.

### O que já existe no engine

`BattleState.newTrainer` (linha ~689) já aplica movesets por slot quando o `partyDef` tem `moves`:
```lua
for i, slot in ipairs(partyDef) do
  local mon = self.enemyParty[i]
  if mon and slot.moves then
    mon.moves = {}
    for _, moveId in ipairs(slot.moves) do
      local mdef = game.data.moves[moveId]
      table.insert(mon.moves, { id = moveId, pp = mdef and mdef.pp or 0 })
    end
  end
end
```
O campo `moves` em cada slot do `partyDef` já é suportado nativamente. **Não é necessário nenhum hook adicional** — basta incluir `moves` nos slots ao fazer o `patch` na fase 2.

### O que precisa ser implementado

1. **Extensão do schema JSON**:
   ```json
   {
     "OPP_BROCK": {
       "character": "CUSTOM_MYCHAR",
       "party": [
         {
           "species": "GEODUDE",
           "level": 12,
           "moves": ["TACKLE", "DEFENSE_CURL", "MUD_SLAP"]
         }
       ]
     }
   }
   ```

2. **Validação** — checar que cada move ID existe em `data.moves`. Emitir `mod.log:warn` para IDs inválidos e omitir apenas o move problemático (não o Pokémon inteiro).

---

## Fase 4 — Substituição Aberta de Qualquer NPC

**User Story:** Como criador, quero substituir qualquer personagem ou NPC do jogo para criar total conversions.

### O que já existe no engine

- `npc.def.sprite` — id do sprite de cada NPC, definido pelo mapa. A lógica de `rival_swap.lua` já itera `ow.npcs` e substituiu por `npc.def.sprite == "SPRITE_BLUE"`.
- `mod.content.maps` — permite registrar/patchear mapas inteiros, incluindo definições de NPCs.
- `mod.content.map_scripts` — permite registrar scripts de talk/step por mapa sem editar arquivos do engine.

### O que precisa ser implementado

1. **Remover o escopo restrito** da fase 1 (que mira somente gym leaders e treinadores-chave). Na fase 4, qualquer `SPRITE_*` id pode aparecer como chave de mapeamento.

2. **Mapeamento por mapa** — adicionar suporte a escopo por mapa no JSON para evitar substituições globais indesejadas:
   ```json
   {
     "SPRITE_YOUNGSTER": {
       "character": "CUSTOM_MYCHAR",
       "maps": ["ROUTE_1", "ROUTE_22"]
     }
   }
   ```
   Sem `maps`, o override é global.

3. **Fallback seguro** — se o Custom Character referenciado não estiver disponível em `AVAILABLE_ID`, logar `mod.log:warn` e não aplicar a substituição. Nunca crashar o jogo.

4. **Performance** — a iteração de `ow.npcs` já é O(n) por mapa. Para mapas com muitos NPCs e muitas regras de mapeamento, pré-indexar o `trainer_map` como `{ [spriteId] = charId }` no load para reduzir a busca por map.entered para O(1) por NPC.

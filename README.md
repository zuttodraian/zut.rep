# Anime Card Farm – Auto Pack

Script para o jogo do Roblox **Anime Card Farm (Fazenda de Cartas de Anime)**.

## Como funciona
1. Clica no botão **Pacote de Spawn** da sua esteira.
2. Lê o nome e o preço do pacote que aparece na esteira.
3. Se o pacote estiver na lista `ALVOS` do `CONFIG`, ele compra (prompt **Comprar / E**).
4. Se faltar dinheiro, ele calcula quanto falta, coleta as Caixas de Carta, vende na loja de caixas
   e repete isso até ter o valor. Depois compra o pacote.

Pacotes que vêm configurados (os marcados no print): Futebol (8.0Qd), Empíreo (30.0Qd),
Bizarro (560.0Qd), Titã (4.2Qn), Evoluído (25.0Qn) e o de 123.0Qn.

## Uso
- Fique na sua base, perto da esteira, e execute `AnimeCardFarm_AutoPack.lua` no executor.
- No painel, clique em **LIGAR**.
- Se não achar o botão, os pacotes ou a venda, clique em **Scanner** e abra o console (F9):
  ele lista prompts, ClickDetectors e remotes para você ajustar as palavras no `CONFIG`.

> Aviso: usar executores/scripts vai contra os Termos de Uso do Roblox e pode causar banimento.
> Use por sua conta e risco, de preferência numa conta alternativa.

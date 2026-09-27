# RPA – Anime Card Farm (Windows)

Robô que joga pela **tela**: clica, aperta teclas e lê os textos do jogo (OCR do próprio Windows).
Ele **não mexe no Roblox** e não precisa de executor.

## 1. Instalar (só uma vez)
1. Instale o **Python** em https://www.python.org/downloads/.
   Na primeira tela do instalador, **marque "Add python.exe to PATH"**.
2. Baixe esta pasta `rpa` (GitHub → botão **Code → Download ZIP**, branch
   `claude/roblox-card-farm-auto-script-e8040e`) e extraia.
3. Dê dois cliques em **`0_instalar.bat`**.

## 2. Calibrar (só uma vez, ou se mudar a câmera ou a resolução)
1. Abra o Roblox, vá para a sua base, **perto da esteira**, e deixe a câmera parada.
2. Clique uma vez no Pacote de Spawn para aparecer um pacote.
3. Rode **`1_calibrar.bat`**. Para cada item, ponha o mouse em cima e aperte **F8**:
   - o botão **Pacote de Spawn**;
   - a área do **nome + preço** do pacote (canto superior esquerdo e inferior direito);
   - a área do seu **dinheiro** (o `$13.28Qn` lá embaixo);
   - os botões **Vender**, **Vender tudo** e **Base** (F9 pula o que não existir).

## 3. Gravar a rota de venda (recomendado)
Rode **`2_gravar_rota_venda.bat`**, aperte **F8** e faça no jogo o caminho completo:
coletar caixas → vender → voltar para o **mesmo lugar** perto da esteira. Aperte **F10** para terminar.
O robô repete essa gravação sempre que faltar dinheiro.
Se não gravar, ele usa só os botões Vender, Vender tudo e Base.
Não gire a câmera com o botão direito durante a gravação.

## 4. Testar a leitura
Rode **`3_testar_leitura.bat`**. Ele mostra o dinheiro e o pacote que ele leu e salva as
imagens em `debug/`. Se a leitura sair errada, calibre de novo pegando uma área mais justa no texto.

## 5. Rodar
Rode **`4_rodar.bat`** e deixe o Roblox visível na tela.
- **F6** pausa e continua. **F7** para.
- Emergência: jogue o mouse no **canto superior esquerdo** da tela.
- Tudo fica registrado em `rpa_log.txt`.

## Pacotes comprados
Estão no topo de `rpa_anime_card_farm.py` (abra com o Bloco de Notas), na lista `ALVOS`.
O robô reconhece o pacote pelo **nome** ou pelo **preço**. Já vêm configurados:
Futebol (8.0Qd), Empíreo (30.0Qd), Bizarro (560.0Qd), Titã (4.2Qn), Evoluído (25.0Qn) e o de 123.0Qn.

## Dicas
- Não mexa o mouse nem a câmera enquanto ele roda; ele usa o seu mouse e o seu teclado.
- Se o Windows estiver com zoom (125% / 150%), o script já corrige as coordenadas.
- Se o OCR não ler bem, instale o pacote de idioma **Português** no Windows
  (Configurações → Hora e idioma → Idioma).

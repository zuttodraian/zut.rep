"""
RPA - Anime Card Farm (Roblox) - Windows
=========================================

Robo que joga pela TELA (mouse + teclado + leitura de texto), sem mexer no
Roblox:

  1. Clica no botao "Pacote de Spawn".
  2. Le (OCR) o nome e o preco do pacote que apareceu na esteira.
  3. Se for um pacote da lista ALVOS -> aperta E para comprar.
  4. Se faltar dinheiro -> executa a rota de venda gravada (coletar caixas
     e vender) ate ter o dinheiro, e entao compra.

Modos (ou use os arquivos .bat):
  python rpa_anime_card_farm.py calibrar   -> marca os pontos da tela
  python rpa_anime_card_farm.py gravar     -> grava a rota de coletar/vender
  python rpa_anime_card_farm.py testar     -> mostra o que o OCR esta lendo
  python rpa_anime_card_farm.py rodar      -> liga o robo

Teclas enquanto roda:  F6 = pausar/continuar   F7 = parar
Emergencia: jogue o mouse no canto superior esquerdo da tela.
"""

import json
import os
import re
import sys
import threading
import time
import unicodedata
from datetime import datetime

# ---------------------------------------------------------------------------
# CONFIGURACAO - edite aqui (abra este arquivo no Bloco de Notas)
# ---------------------------------------------------------------------------

# Pacotes que devem ser comprados. O robo compra se achar o NOME (palavras,
# sem acento) OU se o PRECO lido for igual ao preco configurado.
ALVOS = [
    {"nome": ["futebol", "atacante"],  "preco": "8.0Qd"},    # Pacote Futebol
    {"nome": ["empireo", "sagrado"],   "preco": "30.0Qd"},   # Pacote Empireo
    {"nome": ["bizarro", "paradoxo"],  "preco": "560.0Qd"},  # Pacote Bizarro
    {"nome": ["tita", "fundador"],     "preco": "4.2Qn"},    # Pacote Tita
    {"nome": ["evoluido"],             "preco": "25.0Qn"},   # Pacote Evoluido
    {"nome": [],                       "preco": "123.0Qn"},  # 3a linha (marcado)
]

ESPERA_APOS_SPAWN = 1.2      # segundos entre clicar em Spawn e ler o pacote
ESPERA_ENTRE_SPAWNS = 0.4    # pausa extra quando o pacote nao interessa
ESPERA_ENTRE_VENDAS = 5.0    # tempo para as cartas gerarem mais caixas
TEMPO_MAX_JUNTANDO = 30 * 60 # desiste de juntar dinheiro apos X segundos
TECLA_COMPRAR = "e"
IDIOMAS_OCR = ["pt-BR", "en-US"]  # OCR do proprio Windows

PASTA = os.path.dirname(os.path.abspath(__file__))
ARQ_PONTOS = os.path.join(PASTA, "pontos.json")
ARQ_ROTA = os.path.join(PASTA, "rota.json")
PASTA_DEBUG = os.path.join(PASTA, "debug")
ARQ_LOG = os.path.join(PASTA, "rpa_log.txt")

# ---------------------------------------------------------------------------
# NUMEROS DO JOGO  ($13.28Qn -> 1.328e19)
# ---------------------------------------------------------------------------

SUFIXOS = {
    "": 1, "K": 1e3, "M": 1e6, "B": 1e9, "T": 1e12, "Qd": 1e15, "Qn": 1e18,
    "Sx": 1e21, "Sp": 1e24, "Oc": 1e27, "No": 1e30, "De": 1e33,
}
_RE_VALOR = re.compile(
    r"(?P<cif>[\$S§]?)\s*(?P<num>\d+(?:[.,]\d+)?)\s*"
    r"(?P<suf>Qd|Qn|Sx|Sp|Oc|No|De|K|M|B|T)?(?P<depois>\s*/)?"
)


def _normalizar_ocr(txt):
    """Corrige erros comuns do OCR nos sufixos (Od->Qd, 0n->Qn, ...)."""
    txt = txt.replace("\n", " ")
    txt = re.sub(r"(?<=\d)\s*[O0oQq]\s*d\b", "Qd", txt)
    txt = re.sub(r"(?<=\d)\s*[O0oQq]\s*n\b", "Qn", txt)
    txt = re.sub(r"(?<=\d)\s*[S5s]\s*x\b", "Sx", txt)
    txt = re.sub(r"(?<=\d)\s*[S5s]\s*p\b", "Sp", txt)
    return txt


def ler_valor(txt, exigir_cifrao=False):
    """Acha um valor tipo "$35.0T" no texto. Retorna (numero, texto) ou (None, None)."""
    if not txt:
        return None, None
    txt = _normalizar_ocr(txt)
    candidatos = []
    for m in _RE_VALOR.finditer(txt):
        if m.group("depois"):          # "102.1K/250K" -> barra de progresso
            continue
        if m.start() > 0 and txt[m.start() - 1] == "/":
            continue
        num = float(m.group("num").replace(",", "."))
        suf = m.group("suf") or ""
        tem_cifrao = m.group("cif") == "$"
        tem_cifrao_prov = bool(m.group("cif"))
        if exigir_cifrao and not tem_cifrao_prov:
            continue
        prioridade = (2 if tem_cifrao else 1 if tem_cifrao_prov else 0) + (1 if suf else 0)
        candidatos.append((prioridade, num * SUFIXOS[suf], f"{m.group('num')}{suf}"))
    if not candidatos:
        return None, None
    candidatos.sort(key=lambda c: -c[0])
    return candidatos[0][1], candidatos[0][2]


def formatar(n):
    if n is None:
        return "?"
    for s in ("De", "No", "Oc", "Sp", "Sx", "Qn", "Qd", "T", "B", "M", "K"):
        if n >= SUFIXOS[s]:
            return f"${n / SUFIXOS[s]:.2f}{s}"
    return f"${n:.0f}"


def sem_acento(txt):
    txt = unicodedata.normalize("NFKD", txt or "")
    return "".join(c for c in txt if not unicodedata.combining(c)).lower()


def eh_alvo(texto, preco):
    """Retorna o alvo (dict) se o pacote lido for um dos desejados."""
    t = sem_acento(texto)
    for alvo in ALVOS:
        for palavra in alvo["nome"]:
            if palavra and sem_acento(palavra) in t:
                return alvo
        if preco is not None and alvo.get("preco"):
            p_alvo, _ = ler_valor("$" + alvo["preco"])
            if p_alvo and abs(preco - p_alvo) <= p_alvo * 0.01:
                return alvo
    return None


# ---------------------------------------------------------------------------
# LOG
# ---------------------------------------------------------------------------

def log(msg):
    linha = f"[{datetime.now():%H:%M:%S}] {msg}"
    print(linha, flush=True)
    try:
        with open(ARQ_LOG, "a", encoding="utf-8") as f:
            f.write(linha + "\n")
    except OSError:
        pass


# ---------------------------------------------------------------------------
# BIBLIOTECAS DO WINDOWS (carregadas so quando precisa)
# ---------------------------------------------------------------------------

pdi = mss = Image = ImageOps = kb = mouse = None


def carregar_libs():
    global pdi, mss, Image, ImageOps, kb, mouse
    import ctypes
    try:  # coordenadas em pixels reais mesmo com zoom do Windows (125%, 150%)
        ctypes.windll.shcore.SetProcessDpiAwareness(2)
    except Exception:
        try:
            ctypes.windll.user32.SetProcessDPIAware()
        except Exception:
            pass
    import pydirectinput as _pdi
    import mss as _mss
    from PIL import Image as _Image, ImageOps as _ImageOps
    from pynput import keyboard as _kb, mouse as _mouse
    pdi, mss, Image, ImageOps, kb, mouse = _pdi, _mss, _Image, _ImageOps, _kb, _mouse
    pdi.PAUSE = 0.03
    pdi.FAILSAFE = True


def focar_roblox():
    try:
        import pygetwindow as gw
        janelas = [w for w in gw.getWindowsWithTitle("Roblox") if w.title.strip()]
        if janelas:
            janelas[0].activate()
            time.sleep(0.4)
            return True
    except Exception:
        pass
    return False


# ---------------------------------------------------------------------------
# TELA + OCR
# ---------------------------------------------------------------------------

def capturar(regiao):
    l, t, r, b = regiao
    with mss.mss() as sct:
        shot = sct.grab({"left": l, "top": t, "width": r - l, "height": b - t})
        return Image.frombytes("RGB", shot.size, shot.rgb)


def _variacoes(img):
    """Versoes da imagem que ajudam o OCR com o texto contornado do jogo."""
    grande = img.resize((img.width * 3, img.height * 3), Image.LANCZOS)
    cinza = ImageOps.autocontrast(ImageOps.grayscale(grande))
    claro = cinza.point(lambda p: 0 if p > 170 else 255)   # texto claro -> preto
    return [grande, cinza, claro]


_ocr_motor = None


def _ocr(img):
    global _ocr_motor
    if _ocr_motor is None:
        _ocr_motor = _escolher_motor()
    return _ocr_motor(img)


def _escolher_motor():
    try:
        import winocr

        def motor_win(img):
            for lang in IDIOMAS_OCR:
                try:
                    if hasattr(winocr, "recognize_pil_sync"):
                        r = winocr.recognize_pil_sync(img, lang)
                        return r["text"] if isinstance(r, dict) else getattr(r, "text", "")
                    import asyncio
                    return asyncio.run(winocr.recognize_pil(img, lang)).text
                except Exception:
                    continue
            return ""
        log("OCR: usando o OCR do Windows (winocr)")
        return motor_win
    except ImportError:
        pass
    try:
        import pytesseract
        caminho = r"C:\Program Files\Tesseract-OCR\tesseract.exe"
        if os.path.exists(caminho):
            pytesseract.pytesseract.tesseract_cmd = caminho
        log("OCR: usando Tesseract")
        return lambda img: pytesseract.image_to_string(img, config="--psm 6")
    except ImportError:
        pass
    raise SystemExit("Nenhum OCR instalado. Rode o instalar.bat de novo.")


def ler_regiao(regiao, exigir_cifrao=False, salvar_como=None):
    """Le a regiao da tela. Retorna (texto_completo, valor, valor_txt)."""
    img = capturar(regiao)
    if salvar_como:
        os.makedirs(PASTA_DEBUG, exist_ok=True)
        img.save(os.path.join(PASTA_DEBUG, salvar_como))
    textos, valor, valor_txt = [], None, None
    for v in _variacoes(img):
        t = _ocr(v) or ""
        textos.append(t)
        if valor is None:
            valor, valor_txt = ler_valor(t, exigir_cifrao)
        if valor is not None and len(textos) >= 2:
            break
    return " | ".join(textos), valor, valor_txt


# ---------------------------------------------------------------------------
# MOUSE / TECLADO
# ---------------------------------------------------------------------------

parar = threading.Event()
pausado = threading.Event()


def esperar(seg):
    fim = time.time() + seg
    while time.time() < fim:
        if parar.is_set():
            raise KeyboardInterrupt
        while pausado.is_set() and not parar.is_set():
            time.sleep(0.2)
        time.sleep(min(0.05, max(0, fim - time.time())))


def clicar(ponto, botao="left"):
    x, y = ponto
    pdi.moveTo(x, y)
    pdi.moveRel(2, 0)      # o Roblox so registra o clique se o mouse mexer
    pdi.moveRel(-2, 0)
    pdi.mouseDown(button=botao)
    time.sleep(0.06)
    pdi.mouseUp(button=botao)


def apertar(tecla, segurar=0.08):
    pdi.keyDown(tecla)
    time.sleep(segurar)
    pdi.keyUp(tecla)


# ---------------------------------------------------------------------------
# PONTOS (calibracao)
# ---------------------------------------------------------------------------

def carregar_json(caminho):
    if not os.path.exists(caminho):
        return None
    with open(caminho, encoding="utf-8") as f:
        return json.load(f)


def salvar_json(caminho, dados):
    with open(caminho, "w", encoding="utf-8") as f:
        json.dump(dados, f, indent=2, ensure_ascii=False)


def esperar_tecla(teclas):
    res = {}

    def on_press(k):
        if k in teclas:
            res["k"] = k
            return False
    with kb.Listener(on_press=on_press) as l:
        l.join()
    return res["k"]


def pegar_ponto(descricao, opcional=False):
    extra = "  (F9 = pular)" if opcional else ""
    print(f"\n-> {descricao}\n   Coloque o mouse em cima e aperte F8.{extra}")
    k = esperar_tecla({kb.Key.f8, kb.Key.f9} if opcional else {kb.Key.f8})
    if k == kb.Key.f9:
        print("   pulado.")
        return None
    x, y = mouse.Controller().position
    x, y = int(x), int(y)
    print(f"   ok: ({x}, {y})")
    return [x, y]


def pegar_regiao(descricao):
    print(f"\n== {descricao} ==")
    a = pegar_ponto("canto SUPERIOR ESQUERDO da area")
    b = pegar_ponto("canto INFERIOR DIREITO da area")
    return [min(a[0], b[0]), min(a[1], b[1]), max(a[0], b[0]), max(a[1], b[1])]


def modo_calibrar():
    print(__doc__)
    print("CALIBRACAO - deixe o Roblox aberto na sua base, perto da esteira,")
    print("com a camera parada do jeito que voce vai jogar (nao mexa depois!).")
    print("Antes de comecar, clique 1x no Pacote de Spawn para aparecer um pacote.")
    pontos = {}
    pontos["spawn"] = pegar_ponto("Botao PACOTE DE SPAWN (o verde com '?')")
    pontos["regiao_pacote"] = pegar_regiao(
        "AREA DO NOME + PRECO do pacote (o texto 'Pacote Galactico  $35.0T' acima da esteira).\n"
        "   Pegue uma area com folga, que caiba nome e preco de qualquer pacote")
    pontos["regiao_dinheiro"] = pegar_regiao(
        "AREA DO SEU DINHEIRO (o '$13.28Qn' la embaixo, a esquerda)")
    print("\n== Venda simples (usada se voce NAO gravar uma rota) ==")
    pontos["botao_vender"] = pegar_ponto("Botao VENDER (topo da tela)", opcional=True)
    pontos["botao_vender_tudo"] = pegar_ponto(
        "Botao 'Vender tudo' que aparece depois (abra a loja antes)", opcional=True)
    pontos["botao_base"] = pegar_ponto("Botao BASE (topo da tela, para voltar)", opcional=True)
    salvar_json(ARQ_PONTOS, pontos)
    print(f"\nSalvo em {ARQ_PONTOS}. Agora rode o testar.bat para conferir o OCR.")


# ---------------------------------------------------------------------------
# GRAVAR / REPETIR ROTA (coletar caixas e vender)
# ---------------------------------------------------------------------------

_MAPA_TECLAS = {
    "shift_r": "shiftright", "shift_l": "shiftleft", "ctrl_l": "ctrlleft",
    "ctrl_r": "ctrlright", "alt_l": "altleft", "alt_r": "altright",
    "alt_gr": "altright", "caps_lock": "capslock",
}


def _nome_tecla(k):
    if isinstance(k, kb.KeyCode):
        if k.char:
            return k.char.lower()
        if k.vk and 65 <= k.vk <= 90:
            return chr(k.vk).lower()
        if k.vk and 48 <= k.vk <= 57:
            return chr(k.vk)
        return None
    nome = k.name
    return _MAPA_TECLAS.get(nome, nome)


def modo_gravar():
    print("GRAVAR ROTA DE VENDA")
    print("Faca no jogo, com mouse e teclado, TODO o caminho para:")
    print("  coletar as caixas -> ir vender -> vender tudo -> voltar para a esteira.")
    print("Termine exatamente no mesmo lugar onde comecou (perto da esteira).")
    print("NAO gire a camera com o botao direito durante a gravacao.")
    print("\nAperte F8 para comecar a gravar. Aperte F10 para terminar.")
    esperar_tecla({kb.Key.f8})
    eventos, seguradas = [], set()
    t0 = time.time()
    fim = threading.Event()
    print("GRAVANDO... (F10 termina)")

    def on_press(k):
        if k == kb.Key.f10:
            fim.set()
            return False
        nome = _nome_tecla(k)
        if nome and nome not in seguradas:
            seguradas.add(nome)
            eventos.append({"t": time.time() - t0, "tipo": "tecla", "acao": "down", "tecla": nome})

    def on_release(k):
        nome = _nome_tecla(k)
        if nome and nome in seguradas:
            seguradas.discard(nome)
            eventos.append({"t": time.time() - t0, "tipo": "tecla", "acao": "up", "tecla": nome})

    def on_click(x, y, botao, pressionado):
        if fim.is_set():
            return False
        b = "left" if botao == mouse.Button.left else "right" if botao == mouse.Button.right else None
        if b:
            eventos.append({"t": time.time() - t0, "tipo": "mouse", "acao": "down" if pressionado else "up",
                            "x": int(x), "y": int(y), "botao": b})

    ml = mouse.Listener(on_click=on_click)
    ml.start()
    with kb.Listener(on_press=on_press, on_release=on_release) as kl:
        kl.join()
    ml.stop()
    salvar_json(ARQ_ROTA, {"duracao": time.time() - t0, "eventos": eventos})
    print(f"Rota salva ({len(eventos)} acoes, {time.time() - t0:.1f}s) em {ARQ_ROTA}")


def repetir_rota(rota):
    seguradas = set()
    t0 = time.time()
    try:
        for ev in rota["eventos"]:
            espera = ev["t"] - (time.time() - t0)
            if espera > 0:
                esperar(espera)
            if ev["tipo"] == "tecla":
                if ev["acao"] == "down":
                    pdi.keyDown(ev["tecla"])
                    seguradas.add(ev["tecla"])
                else:
                    pdi.keyUp(ev["tecla"])
                    seguradas.discard(ev["tecla"])
            else:
                pdi.moveTo(ev["x"], ev["y"])
                if ev["acao"] == "down":
                    pdi.moveRel(2, 0)
                    pdi.moveRel(-2, 0)
                    pdi.mouseDown(button=ev["botao"])
                else:
                    pdi.mouseUp(button=ev["botao"])
    finally:
        for t in seguradas:
            pdi.keyUp(t)


def venda_simples(pontos):
    if pontos.get("botao_vender"):
        clicar(pontos["botao_vender"])
        esperar(2.0)
        apertar(TECLA_COMPRAR)  # caso a loja seja um prompt "E Vender"
        esperar(1.0)
    if pontos.get("botao_vender_tudo"):
        clicar(pontos["botao_vender_tudo"])
        esperar(1.0)
    if pontos.get("botao_base"):
        clicar(pontos["botao_base"])
        esperar(2.5)


# ---------------------------------------------------------------------------
# ROBO
# ---------------------------------------------------------------------------

def ler_dinheiro(pontos, debug=False):
    _, valor, _ = ler_regiao(pontos["regiao_dinheiro"], exigir_cifrao=False,
                             salvar_como="dinheiro.png" if debug else None)
    return valor


def ler_pacote(pontos, debug=False):
    texto, preco, preco_txt = ler_regiao(pontos["regiao_pacote"], exigir_cifrao=True,
                                         salvar_como="pacote.png" if debug else None)
    if preco is None:  # tenta sem exigir "$"
        preco, preco_txt = ler_valor(texto)
    return texto, preco, preco_txt


def juntar_dinheiro(pontos, rota, preciso):
    inicio = time.time()
    while time.time() - inicio < TEMPO_MAX_JUNTANDO:
        tenho = ler_dinheiro(pontos)
        if tenho is not None and tenho >= preciso:
            return True
        falta = preciso - tenho if tenho is not None else None
        log(f"Faltam {formatar(falta)} (tenho {formatar(tenho)}, preciso {formatar(preciso)}) -> coletando/vendendo")
        if rota:
            repetir_rota(rota)
        else:
            venda_simples(pontos)
        esperar(ESPERA_ENTRE_VENDAS)
    log("Tempo maximo juntando dinheiro atingido.")
    return False


def comprar(pontos, preco):
    antes = ler_dinheiro(pontos)
    apertar(TECLA_COMPRAR)
    esperar(0.8)
    depois = ler_dinheiro(pontos)
    if antes is not None and depois is not None and depois < antes:
        log(f"COMPRADO! Dinheiro {formatar(antes)} -> {formatar(depois)}")
        return True
    apertar(TECLA_COMPRAR)  # segunda tentativa
    esperar(0.8)
    return False


def iniciar_atalhos():
    def on_press(k):
        if k == kb.Key.f6:
            if pausado.is_set():
                pausado.clear()
                log("Continuando...")
            else:
                pausado.set()
                log("PAUSADO (F6 para continuar)")
        elif k == kb.Key.f7:
            log("Parando...")
            parar.set()
            return False
    kb.Listener(on_press=on_press).start()


def modo_rodar():
    pontos = carregar_json(ARQ_PONTOS)
    if not pontos:
        raise SystemExit("Faca a calibracao primeiro (calibrar.bat).")
    rota = carregar_json(ARQ_ROTA)
    log("Rota de venda: " + ("gravada (rota.json)" if rota else "venda simples (botoes)"))
    iniciar_atalhos()
    log("Comecando em 3s... Deixe o Roblox na tela. F6 pausa, F7 para.")
    focar_roblox()
    esperar(3)
    compras = spawns = 0
    try:
        while not parar.is_set():
            clicar(pontos["spawn"])
            spawns += 1
            esperar(ESPERA_APOS_SPAWN)
            texto, preco, preco_txt = ler_pacote(pontos)
            alvo = eh_alvo(texto, preco)
            resumo = re.sub(r"\s+", " ", texto.split("|")[0]).strip()[:60]
            if not alvo:
                log(f"#{spawns} ignorado: {resumo!r} preco={preco_txt}")
                esperar(ESPERA_ENTRE_SPAWNS)
                continue

            if preco is None and alvo.get("preco"):
                preco, _ = ler_valor("$" + alvo["preco"])
            log(f"#{spawns} ALVO encontrado: {resumo!r} preco={formatar(preco)}")
            tenho = ler_dinheiro(pontos)
            if preco is not None and tenho is not None and tenho < preco:
                if not juntar_dinheiro(pontos, rota, preco):
                    continue
                # confere se o pacote ainda esta la depois de vender
                texto2, preco2, _ = ler_pacote(pontos)
                if not eh_alvo(texto2, preco2):
                    log("O pacote sumiu enquanto juntava dinheiro. Voltando a spawnar.")
                    continue
            elif tenho is None:
                log("Nao consegui ler o dinheiro; tentando comprar mesmo assim.")
            if comprar(pontos, preco):
                compras += 1
            log(f"Total: {compras} compras em {spawns} spawns")
    except KeyboardInterrupt:
        pass
    except Exception as e:  # pydirectinput.FailSafeException etc.
        log(f"Parado: {e!r}")
    log(f"Fim. {compras} compras em {spawns} spawns.")


def modo_testar():
    pontos = carregar_json(ARQ_PONTOS)
    if not pontos:
        raise SystemExit("Faca a calibracao primeiro (calibrar.bat).")
    print("Lendo a tela em 3s (deixe o Roblox visivel)...")
    focar_roblox()
    time.sleep(3)
    din = ler_dinheiro(pontos, debug=True)
    texto, preco, preco_txt = ler_pacote(pontos, debug=True)
    print("\n--- RESULTADO ---")
    print(f"Dinheiro lido : {formatar(din)}")
    print(f"Texto pacote  : {texto!r}")
    print(f"Preco pacote  : {preco_txt} -> {formatar(preco)}")
    alvo = eh_alvo(texto, preco)
    print(f"E um alvo?    : {'SIM ' + str(alvo) if alvo else 'nao'}")
    print(f"\nAs imagens capturadas estao em {PASTA_DEBUG} (pacote.png, dinheiro.png).")
    print("Se a leitura estiver errada, refaca a calibracao pegando uma area melhor.")


def main():
    modo = sys.argv[1] if len(sys.argv) > 1 else ""
    modos = {"calibrar": modo_calibrar, "gravar": modo_gravar,
             "testar": modo_testar, "rodar": modo_rodar}
    if modo not in modos:
        print(__doc__)
        return
    carregar_libs()
    modos[modo]()


if __name__ == "__main__":
    main()

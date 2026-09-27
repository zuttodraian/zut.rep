--[[
    Anime Card Farm (Fazenda de Cartas de Anime) - Auto Pack
    ---------------------------------------------------------
    O que faz:
      1. Clica no botao "Pacote de Spawn" da SUA esteira.
      2. Le o nome/preco do pacote que apareceu na esteira.
      3. Se for um dos pacotes da lista ALVOS, compra (prompt "Comprar" / tecla E).
      4. Se nao tiver dinheiro, calcula quanto falta, coleta as Caixas de Carta
         geradas pelas suas cartas, vende na loja de caixas e repete ate ter o
         dinheiro. Depois tenta comprar.

    Como usar:
      - Fique na sua base, perto da esteira, e execute o script no executor.
      - Um painel pequeno aparece no canto da tela (Ligar/Desligar + Scanner).
      - Se algo nao for encontrado, clique em "Scanner" e olhe o console (F9):
        ele lista prompts, botoes e remotes do jogo para voce ajustar o CONFIG.
]]

----------------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------------
local CONFIG = {
    -- Pacotes que devem ser comprados. Casa por NOME (parte do texto)
    -- OU por PRECO exato como aparece no jogo. Deixe o que quiser.
    ALVOS = {
        { nome = "Futebol",  preco = "8.0Qd"   }, -- Pacote Futebol   (Atacante)
        { nome = "Emp",      preco = "30.0Qd"  }, -- Pacote Empireo   (Sagrado)
        { nome = "Bizarro",  preco = "560.0Qd" }, -- Pacote Bizarro   (Paradoxo)
        { nome = "Tit",      preco = "4.2Qn"   }, -- Pacote Tita      (Fundador)
        { nome = "Evolu",    preco = "25.0Qn"  }, -- Pacote Evoluido  (Evoluido)
        { nome = nil,        preco = "123.0Qn" }, -- pacote da 3a linha marcado
    },

    DELAY_SPAWN        = 0.6,  -- espera apos clicar em Pacote de Spawn
    DELAY_LOOP         = 0.25,
    RAIO_BASE          = 160,  -- raio (studs) em volta do botao de spawn = sua base
    TEMPO_MAX_FARM     = 600,  -- segundos maximos tentando juntar dinheiro por pacote
    VOLTAR_APOS_VENDER = true, -- teleporta de volta para a esteira depois de vender

    -- Palavras usadas para achar coisas no jogo (PT e EN)
    PALAVRAS_SPAWN   = { "pacote de spawn", "spawn pack", "spawn" },
    PALAVRAS_COMPRAR = { "comprar", "buy", "purchase" },
    PALAVRAS_COLETAR = { "coletar", "pegar", "collect", "pick", "claim", "caixa", "box" },
    PALAVRAS_VENDER  = { "vender tudo", "sell all", "vender", "sell" },
}

----------------------------------------------------------------------
-- SERVICOS
----------------------------------------------------------------------
local Players    = game:GetService("Players")
local VIM        = game:GetService("VirtualInputManager")
local GuiService = game:GetService("GuiService")
local LP         = Players.LocalPlayer
local PlayerGui  = LP:WaitForChild("PlayerGui")

local ligado  = false
local status  = "Parado"
local botaoSpawn -- instancia do botao de spawn da sua base

local function log(...)
    print("[AutoPack]", ...)
end

local function setStatus(s)
    status = s
    log(s)
end

local function hrp()
    local c = LP.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function lower(s)
    return string.lower(tostring(s or ""))
end

local function contemAlguma(texto, lista)
    texto = lower(texto)
    for _, p in ipairs(lista) do
        if string.find(texto, lower(p), 1, true) then
            return true
        end
    end
    return false
end

----------------------------------------------------------------------
-- NUMEROS ($13.28Qn -> 1.328e19)
----------------------------------------------------------------------
local SUFIXOS = {
    K = 1e3, M = 1e6, B = 1e9, T = 1e12, Qd = 1e15, Qn = 1e18,
    Sx = 1e21, Sp = 1e24, Oc = 1e27, No = 1e30, De = 1e33,
}

local function parseValor(txt)
    if type(txt) == "number" then return txt end
    txt = tostring(txt or ""):gsub(",", ""):gsub("%s", "")
    local num, suf = string.match(txt, "%$?([%d%.]+)(%a*)")
    num = tonumber(num)
    if not num then return nil end
    if suf == "" then return num end
    local mult = SUFIXOS[suf]
        or SUFIXOS[suf:sub(1, 1):upper() .. suf:sub(2):lower()]
        or SUFIXOS[suf:upper()]
    return mult and num * mult or nil
end

local function formatar(n)
    local ordem = { "De", "No", "Oc", "Sp", "Sx", "Qn", "Qd", "T", "B", "M", "K" }
    for _, s in ipairs(ordem) do
        if n >= SUFIXOS[s] then
            return string.format("$%.2f%s", n / SUFIXOS[s], s)
        end
    end
    return string.format("$%.0f", n)
end

----------------------------------------------------------------------
-- DINHEIRO ATUAL
----------------------------------------------------------------------
local function guiVisivel(g)
    local o = g
    while o and o ~= PlayerGui do
        if o:IsA("GuiObject") and not o.Visible then return false end
        if o:IsA("ScreenGui") and not o.Enabled then return false end
        o = o.Parent
    end
    return g.AbsoluteSize.X > 0
end

local function lerDinheiro()
    -- 1) leaderstats
    local ls = LP:FindFirstChild("leaderstats")
    if ls then
        for _, v in ipairs(ls:GetChildren()) do
            if contemAlguma(v.Name, { "dinheiro", "money", "cash", "coins" }) then
                local n = parseValor(v.Value)
                if n then return n end
            end
        end
    end
    -- 2) Texto grande "$13.28Qn" no canto inferior esquerdo da tela
    local melhor, melhorAltura = nil, 0
    local tela = workspace.CurrentCamera.ViewportSize
    for _, g in ipairs(PlayerGui:GetDescendants()) do
        if g:IsA("TextLabel") and guiVisivel(g) then
            local t = g.Text:gsub("<[^>]->", "")
            if string.match(t, "^%s*%$[%d%.,]+%a*%s*$") then
                local pos = g.AbsolutePosition
                if pos.X < tela.X * 0.4 and pos.Y > tela.Y * 0.6
                    and g.AbsoluteSize.Y > melhorAltura then
                    melhor, melhorAltura = t, g.AbsoluteSize.Y
                end
            end
        end
    end
    return melhor and parseValor(melhor) or 0
end

----------------------------------------------------------------------
-- ACOES (clicar, prompt, tocar)
----------------------------------------------------------------------
local function dispararPrompt(p)
    local okFn = typeof(fireproximityprompt) == "function"
    local oldDist, oldHold = p.MaxActivationDistance, p.HoldDuration
    pcall(function()
        p.MaxActivationDistance = math.huge
        p.HoldDuration = 0
        p.RequiresLineOfSight = false
    end)
    if okFn then
        pcall(fireproximityprompt, p)
    else
        pcall(function()
            p:InputHoldBegin()
            task.wait()
            p:InputHoldEnd()
        end)
    end
    task.delay(0.2, function()
        pcall(function()
            p.MaxActivationDistance = oldDist
            p.HoldDuration = oldHold
        end)
    end)
end

local function clicarGui(btn)
    if typeof(firesignal) == "function" then
        local ok = pcall(function()
            firesignal(btn.MouseButton1Click)
            firesignal(btn.Activated)
        end)
        if ok then return end
    end
    if typeof(getconnections) == "function" then
        local ok = pcall(function()
            for _, c in ipairs(getconnections(btn.MouseButton1Click)) do c:Fire() end
            for _, c in ipairs(getconnections(btn.Activated)) do c:Fire() end
        end)
        if ok then return end
    end
    -- fallback: clique real do mouse na posicao do botao
    local inset = GuiService:GetGuiInset()
    local p = btn.AbsolutePosition + btn.AbsoluteSize / 2 + inset
    VIM:SendMouseButtonEvent(p.X, p.Y, 0, true, game, 0)
    task.wait(0.05)
    VIM:SendMouseButtonEvent(p.X, p.Y, 0, false, game, 0)
end

local function tocar(part)
    local r = hrp()
    if not r or not part:IsA("BasePart") then return end
    if typeof(firetouchinterest) == "function" then
        firetouchinterest(r, part, 0)
        task.wait()
        firetouchinterest(r, part, 1)
    else
        local old = r.CFrame
        r.CFrame = part.CFrame
        task.wait(0.15)
        r.CFrame = old
    end
end

local function parteDe(inst)
    if not inst then return nil end
    if inst:IsA("BasePart") then return inst end
    if inst:IsA("Attachment") then return inst.Parent end
    if inst:IsA("Model") then return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true) end
    return inst:FindFirstAncestorWhichIsA("BasePart")
end

local function posicaoDe(inst)
    local p = parteDe(inst)
    return p and p.Position
end

-- Aciona qualquer coisa "clicavel" dentro de um objeto 3D
local function acionar(obj)
    local raiz = obj:FindFirstAncestorWhichIsA("Model") or obj.Parent or obj
    local feito = false
    for _, d in ipairs(raiz:GetDescendants()) do
        if d:IsA("ClickDetector") and typeof(fireclickdetector) == "function" then
            pcall(fireclickdetector, d); feito = true
        elseif d:IsA("ProximityPrompt") and d.Enabled then
            dispararPrompt(d); feito = true
        elseif (d:IsA("TextButton") or d:IsA("ImageButton")) then
            clicarGui(d); feito = true
        end
    end
    if not feito then
        local p = parteDe(obj)
        if p then tocar(p) end
    end
end

----------------------------------------------------------------------
-- ACHAR BOTAO "PACOTE DE SPAWN" DA SUA BASE
----------------------------------------------------------------------
local function textoDe(inst)
    if inst:IsA("TextLabel") or inst:IsA("TextButton") then return inst.Text end
    if inst:IsA("ProximityPrompt") then return inst.ActionText .. " " .. inst.ObjectText end
    return ""
end

local function acharBotaoSpawn()
    local r = hrp()
    local melhor, melhorDist = nil, math.huge
    for _, d in ipairs(workspace:GetDescendants()) do
        local t = textoDe(d)
        if t ~= "" and contemAlguma(t, CONFIG.PALAVRAS_SPAWN) then
            local alvo = d
            -- sobe do texto (SurfaceGui/BillboardGui) ate a peca 3D
            local gui = d:FindFirstAncestorWhichIsA("SurfaceGui") or d:FindFirstAncestorWhichIsA("BillboardGui")
            if gui then
                alvo = gui.Adornee or gui.Parent
            end
            local pos = posicaoDe(alvo)
            if pos and r then
                local dist = (pos - r.Position).Magnitude
                if dist < melhorDist then
                    melhor, melhorDist = alvo, dist
                end
            end
        end
    end
    -- tambem procura um botao de spawn na tela (GUI)
    if not melhor then
        for _, g in ipairs(PlayerGui:GetDescendants()) do
            if (g:IsA("TextButton") or g:IsA("ImageButton")) and guiVisivel(g) then
                local t = g:IsA("TextButton") and g.Text or ""
                for _, c in ipairs(g:GetDescendants()) do t = t .. " " .. textoDe(c) end
                if contemAlguma(t .. " " .. g.Name, CONFIG.PALAVRAS_SPAWN) then
                    return g
                end
            end
        end
    end
    return melhor
end

local function clicarSpawn()
    if not botaoSpawn or not botaoSpawn.Parent then
        botaoSpawn = acharBotaoSpawn()
        if not botaoSpawn then
            setStatus("Botao 'Pacote de Spawn' nao encontrado - fique perto dele")
            return false
        end
        log("Botao de spawn:", botaoSpawn:GetFullName())
    end
    if botaoSpawn:IsA("GuiButton") then
        clicarGui(botaoSpawn)
    else
        acionar(botaoSpawn)
    end
    return true
end

local baseFixa -- posicao da base guardada ao ligar (nao muda com teleportes)

local function centroBase()
    if botaoSpawn and not botaoSpawn:IsA("GuiObject") then
        local p = posicaoDe(botaoSpawn)
        if p then return p end
    end
    if baseFixa then return baseFixa end
    local r = hrp()
    return r and r.Position
end

local function naBase(pos)
    local c = centroBase()
    return pos and c and (pos - c).Magnitude <= CONFIG.RAIO_BASE
end

----------------------------------------------------------------------
-- LER PACOTES NA ESTEIRA
----------------------------------------------------------------------
-- Junta todos os textos ligados a um pacote (billboards dentro dele ou
-- apontando para ele via Adornee).
local function textosDoPacote(modelo, prompt)
    local textos = { prompt.ObjectText, prompt.ActionText, modelo.Name }
    for _, d in ipairs(modelo:GetDescendants()) do
        if d:IsA("TextLabel") then table.insert(textos, d.Text) end
    end
    for _, gui in ipairs(PlayerGui:GetDescendants()) do
        if gui:IsA("BillboardGui") and gui.Adornee and gui.Adornee:IsDescendantOf(modelo) then
            for _, d in ipairs(gui:GetDescendants()) do
                if d:IsA("TextLabel") then table.insert(textos, d.Text) end
            end
        end
    end
    return textos
end

local function precoDosTextos(textos)
    for _, t in ipairs(textos) do
        local limpo = t:gsub("<[^>]->", ""):gsub("%s", "")
        local p = string.match(limpo, "^%$([%d%.]+%a*)$")
        if p then return p end
    end
    return nil
end

local function ehAlvo(textos, precoTxt)
    local tudo = lower(table.concat(textos, " | "))
    for _, a in ipairs(CONFIG.ALVOS) do
        if a.nome and string.find(tudo, lower(a.nome), 1, true) then
            return true, a
        end
        if a.preco and precoTxt and lower(precoTxt) == lower(a.preco) then
            return true, a
        end
    end
    return false
end

local function pacotesNaEsteira()
    local lista = {}
    for _, p in ipairs(workspace:GetDescendants()) do
        if p:IsA("ProximityPrompt") and p.Enabled
            and contemAlguma(p.ActionText, CONFIG.PALAVRAS_COMPRAR) then
            local pos = posicaoDe(p.Parent)
            if naBase(pos) then
                local modelo = p:FindFirstAncestorWhichIsA("Model") or p.Parent
                local textos = textosDoPacote(modelo, p)
                local precoTxt = precoDosTextos(textos)
                table.insert(lista, {
                    prompt = p,
                    modelo = modelo,
                    textos = textos,
                    precoTxt = precoTxt,
                    preco = precoTxt and parseValor(precoTxt) or nil,
                })
            end
        end
    end
    return lista
end

----------------------------------------------------------------------
-- FARMAR DINHEIRO: coletar caixas e vender
----------------------------------------------------------------------
local function coletarCaixas()
    local n = 0
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("ProximityPrompt") and d.Enabled
            and contemAlguma(d.ActionText .. " " .. d.ObjectText, CONFIG.PALAVRAS_COLETAR)
            and not contemAlguma(d.ActionText, CONFIG.PALAVRAS_COMPRAR)
            and naBase(posicaoDe(d.Parent)) then
            dispararPrompt(d); n = n + 1
        elseif d:IsA("BasePart") and d:FindFirstChildWhichIsA("TouchTransmitter")
            and contemAlguma(d.Name .. " " .. (d.Parent and d.Parent.Name or ""), { "box", "caixa", "crate", "collect", "coletar" })
            and naBase(d.Position) then
            tocar(d); n = n + 1
        end
    end
    return n
end

local function botoesGuiCom(palavras)
    local achados = {}
    for _, g in ipairs(PlayerGui:GetDescendants()) do
        if (g:IsA("TextButton") or g:IsA("ImageButton")) and guiVisivel(g) then
            local t = (g:IsA("TextButton") and g.Text or "") .. " " .. g.Name
            for _, c in ipairs(g:GetDescendants()) do
                if c:IsA("TextLabel") then t = t .. " " .. c.Text end
            end
            if contemAlguma(t, palavras) then table.insert(achados, g) end
        end
    end
    return achados
end

local function vender()
    local r = hrp()
    local volta = r and r.CFrame
    local vendeu = false

    -- 1) Prompt "Vender" na loja de caixas da base
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("ProximityPrompt") and d.Enabled
            and contemAlguma(d.ActionText .. " " .. d.ObjectText, CONFIG.PALAVRAS_VENDER)
            and naBase(posicaoDe(d.Parent)) then
            local p = parteDe(d.Parent)
            if p and r then r.CFrame = p.CFrame + Vector3.new(0, 3, 0) task.wait(0.3) end
            dispararPrompt(d)
            vendeu = true
            task.wait(0.5)
        end
    end

    -- 2) Botao "Vender" do topo (teleporta p/ loja) e depois "Vender Tudo"
    if not vendeu then
        for _, b in ipairs(botoesGuiCom({ "vender", "sell" })) do
            clicarGui(b)
            task.wait(1)
            break
        end
        -- apos teleportar, tenta prompts de venda perto do jogador
        local r2 = hrp()
        for _, d in ipairs(workspace:GetDescendants()) do
            if d:IsA("ProximityPrompt") and d.Enabled
                and contemAlguma(d.ActionText .. " " .. d.ObjectText, CONFIG.PALAVRAS_VENDER) then
                local pos = posicaoDe(d.Parent)
                if pos and r2 and (pos - r2.Position).Magnitude < 60 then
                    dispararPrompt(d); vendeu = true
                end
            end
        end
        -- botoes de "Vender tudo" que abriram na tela
        task.wait(0.5)
        for _, b in ipairs(botoesGuiCom({ "vender tudo", "sell all" })) do
            clicarGui(b); vendeu = true
        end
    end

    if CONFIG.VOLTAR_APOS_VENDER and volta and hrp() then
        task.wait(0.3)
        hrp().CFrame = volta
    end
    return vendeu
end

local function farmarAte(valor)
    local inicio = os.clock()
    while ligado and os.clock() - inicio < CONFIG.TEMPO_MAX_FARM do
        local din = lerDinheiro()
        if din >= valor then return true end
        setStatus(("Faltam %s (tenho %s, preciso %s) - farmando caixas")
            :format(formatar(valor - din), formatar(din), formatar(valor)))
        coletarCaixas()
        task.wait(0.5)
        vender()
        task.wait(1)
    end
    return lerDinheiro() >= valor
end

----------------------------------------------------------------------
-- COMPRAR
----------------------------------------------------------------------
local function comprar(pac)
    local r = hrp()
    local p = parteDe(pac.prompt.Parent)
    if r and p then
        r.CFrame = CFrame.new(p.Position + Vector3.new(0, 3, 4), p.Position)
        task.wait(0.15)
    end
    dispararPrompt(pac.prompt)
end

local tentados = setmetatable({}, { __mode = "k" })

local function loopPrincipal()
    while ligado do
        local pacs = pacotesNaEsteira()
        local alvoAchado = nil
        for _, pac in ipairs(pacs) do
            local ok, info = ehAlvo(pac.textos, pac.precoTxt)
            if ok and not tentados[pac.prompt] then
                alvoAchado = pac
                pac.info = info
                break
            end
        end

        if alvoAchado then
            local pac = alvoAchado
            local nome = (pac.info and pac.info.nome) or pac.precoTxt or "?"
            local din = lerDinheiro()
            if pac.preco and din < pac.preco then
                setStatus(("Pacote alvo %s custa %s, tenho %s")
                    :format(nome, formatar(pac.preco), formatar(din)))
                farmarAte(pac.preco)
            end
            if ligado and pac.prompt.Parent and pac.prompt.Enabled then
                setStatus("Comprando pacote " .. nome .. " (" .. tostring(pac.precoTxt) .. ")")
                comprar(pac)
                task.wait(0.5)
                if pac.prompt.Parent and pac.prompt.Enabled then
                    -- ainda existe: talvez faltou dinheiro (preco nao lido). Tenta de novo depois
                    task.wait(0.5)
                    comprar(pac)
                end
            else
                setStatus("O pacote " .. nome .. " sumiu da esteira antes da compra")
            end
            tentados[pac.prompt] = true
        else
            setStatus("Spawnando pacotes...")
            clicarSpawn()
            task.wait(CONFIG.DELAY_SPAWN)
        end
        task.wait(CONFIG.DELAY_LOOP)
    end
    setStatus("Parado")
end

----------------------------------------------------------------------
-- SCANNER (ajuda a ajustar o CONFIG) - resultado no console F9
----------------------------------------------------------------------
local function scanner()
    log("===== SCANNER =====")
    log("Dinheiro lido:", formatar(lerDinheiro()))
    local b = acharBotaoSpawn()
    log("Botao spawn:", b and b:GetFullName() or "NAO ACHADO")
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("ProximityPrompt") and naBase(posicaoDe(d.Parent)) then
            log(("Prompt: '%s' / '%s' -> %s"):format(d.ActionText, d.ObjectText, d:GetFullName()))
        elseif d:IsA("ClickDetector") and naBase(posicaoDe(d.Parent)) then
            log("ClickDetector ->", d:GetFullName())
        end
    end
    for _, pac in ipairs(pacotesNaEsteira()) do
        log("Pacote na esteira:", table.concat(pac.textos, " | "), "preco:", tostring(pac.precoTxt))
    end
    local rs = game:GetService("ReplicatedStorage")
    for _, d in ipairs(rs:GetDescendants()) do
        if (d:IsA("RemoteEvent") or d:IsA("RemoteFunction"))
            and contemAlguma(d.Name, { "spawn", "buy", "sell", "collect", "pack", "box", "vender", "comprar" }) then
            log("Remote:", d.ClassName, d:GetFullName())
        end
    end
    log("===================")
end

----------------------------------------------------------------------
-- PAINEL
----------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "AutoPackGui"
gui.ResetOnSpawn = false
pcall(function() gui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
if not gui.Parent then gui.Parent = PlayerGui end

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(240, 110)
frame.Position = UDim2.new(1, -250, 0.5, -55)
frame.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
frame.Active = true
frame.Draggable = true
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

local titulo = Instance.new("TextLabel")
titulo.Size = UDim2.new(1, 0, 0, 22)
titulo.BackgroundTransparency = 1
titulo.Text = "Anime Card Farm - Auto Pack"
titulo.TextColor3 = Color3.new(1, 1, 1)
titulo.Font = Enum.Font.GothamBold
titulo.TextSize = 13
titulo.Parent = frame

local lblStatus = Instance.new("TextLabel")
lblStatus.Size = UDim2.new(1, -10, 0, 40)
lblStatus.Position = UDim2.fromOffset(5, 22)
lblStatus.BackgroundTransparency = 1
lblStatus.TextWrapped = true
lblStatus.TextColor3 = Color3.fromRGB(200, 200, 200)
lblStatus.Font = Enum.Font.Gotham
lblStatus.TextSize = 11
lblStatus.Parent = frame

local function criarBotao(texto, x, cor)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(110, 34)
    b.Position = UDim2.fromOffset(x, 68)
    b.BackgroundColor3 = cor
    b.Text = texto
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 13
    b.Parent = frame
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    return b
end

local btnToggle  = criarBotao("LIGAR", 7, Color3.fromRGB(40, 160, 70))
local btnScanner = criarBotao("Scanner (F9)", 123, Color3.fromRGB(60, 90, 180))

btnToggle.MouseButton1Click:Connect(function()
    ligado = not ligado
    btnToggle.Text = ligado and "DESLIGAR" or "LIGAR"
    btnToggle.BackgroundColor3 = ligado and Color3.fromRGB(180, 50, 50) or Color3.fromRGB(40, 160, 70)
    if ligado then
        local r = hrp()
        baseFixa = r and r.Position
        botaoSpawn = acharBotaoSpawn()
        task.spawn(loopPrincipal)
    end
end)

btnScanner.MouseButton1Click:Connect(function()
    task.spawn(scanner)
end)

task.spawn(function()
    while gui.Parent do
        lblStatus.Text = status .. "\nDinheiro: " .. formatar(lerDinheiro())
        task.wait(0.5)
    end
end)

log("Carregado. Clique em LIGAR no painel.")

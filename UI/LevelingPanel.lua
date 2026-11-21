--===========================================================================
-- EzWoW - Profession Recipes
-- UI/LevelingPanel.lua : Skill-Up Planner Window ("Level up" tab)
--===========================================================================
-- Sits to the right of the profession window (or on its own with /ezpr level):
-- a skill bar (now -> target, training caps marked), a summary (crafts, cost at
-- the auction house and at vendors, what the bags and bank save), the steps (what
-- to make, how many, the materials of one craft, where it turns yellow / green,
-- how many the bags allow now), one grouped shopping list (make / auction /
-- vendor / no price / already enough) and a button that picks the next recipe in
-- the profession window with the count filled in.
local ADDON, ns = ...
local type, pairs, ipairs, tonumber, tostring, pcall = type, pairs, ipairs, tonumber, tostring, pcall
local floor, max, min = math.floor, math.max, math.min

local Leveling = ns.Leveling
local Prices = Leveling.Prices
local Theme = ns.Style
local R_SPELL, R_ITEM, R_REAG = ns.R_SPELL, ns.R_ITEM, ns.R_REAG
local PREFIX = "|cffeba86aEzWoW - Profession Recipes|r: "

-----------------------------------------------------------------------------
-- Texts (ko, en, de, fr, es, ru, zhCN, zhTW)
-----------------------------------------------------------------------------
local LANGS = { ko = 1, en = 2, de = 3, fr = 4, es = 5, ru = 6, zhCN = 7, zhTW = 8 }
local TEXT = {
    tab = { "올리기", "Level up", "Hochleveln", "Monter", "Subir", "Прокачка", "冲技能", "衝技能" },
    tabTip = {
        "전문 기술 올리기\n지금 숙련도에서 목표까지 무엇을 몇 개 만들지, 필요한 재료와 경매장 비용을 보여 줍니다.",
        "Level up\nWhat to make, and how many, from your skill to a target, with the materials and their auction cost.",
        "Hochleveln\nWas und wie viel du bis zum Ziel herstellst, mit Materialien und Auktionskosten.",
        "Monter\nQuoi fabriquer et combien jusqu'à l'objectif, avec les composants et leur coût à l'hôtel des ventes.",
        "Subir\nQué fabricar y cuántos hasta el objetivo, con los materiales y su coste en la casa de subastas.",
        "Прокачка\nЧто и сколько делать до цели, с материалами и их ценой на аукционе.",
        "冲技能\n从当前技能到目标要做什么、做多少，以及所需材料和拍卖行花费。",
        "衝技能\n從目前技能到目標要做什麼、做多少，以及所需材料與拍賣場花費。",
    },
    title = { "%s 올리기", "Level up %s", "%s hochleveln", "Monter %s", "Subir %s", "Прокачка: %s", "%s 冲技能", "%s 衝技能" },
    skillBar = { "%d / %d  →  목표 %d", "%d / %d  →  target %d", "%d / %d  →  Ziel %d", "%d / %d  →  objectif %d", "%d / %d  →  objetivo %d", "%d / %d  →  цель %d", "%d / %d  →  目标 %d", "%d / %d  →  目標 %d" },
    skillBarNoCap = { "%d  →  목표 %d", "%d  →  target %d", "%d  →  Ziel %d", "%d  →  objectif %d", "%d  →  objetivo %d", "%d  →  цель %d", "%d  →  目标 %d", "%d  →  目標 %d" },
    notLearned = { "배우지 않음  →  목표 %d", "Not learned  →  target %d", "Nicht erlernt  →  Ziel %d", "Non appris  →  objectif %d", "Sin aprender  →  objetivo %d", "Не изучено  →  цель %d", "未学习  →  目标 %d", "未學習  →  目標 %d" },
    target = { "목표", "Target", "Ziel", "Objectif", "Objetivo", "Цель", "目标", "目標" },
    targetTip = {
        "클릭: 5씩 · Shift+클릭: 25씩",
        "Click: by 5 · Shift-click: by 25",
        "Klick: um 5 · Umschalt-Klick: um 25",
        "Clic : de 5 · Maj-clic : de 25",
        "Clic: de 5 en 5 · Mayús-clic: de 25 en 25",
        "Щелчок: по 5 · Shift-щелчок: по 25",
        "点击：每次 5 · Shift+点击：每次 25",
        "點擊：每次 5 · Shift+點擊：每次 25",
    },
    trainer = { "상급자 제조법 포함", "Trainer recipes", "Lehrer-Rezepte", "Recettes du maître", "Recetas del instructor", "Рецепты учителя", "包括训练师配方", "包括訓練師配方" },
    trainerTip = {
        "아직 배우지 않았어도 상급자에게 배울 수 있는 제조법을 경로에 넣습니다.",
        "Also plans with recipes a trainer teaches that you have not learned yet.",
        "Plant auch mit Lehrer-Rezepten, die du noch nicht kennst.",
        "Prévoit aussi les recettes d'un maître que vous n'avez pas encore apprises.",
        "También usa recetas del instructor que aún no has aprendido.",
        "Учитывает и рецепты учителя, которые вы ещё не изучили.",
        "也使用尚未学会、可向训练师学习的配方。",
        "也使用尚未學會、可向訓練師學習的配方。",
    },
    prof = { "전문 기술", "Profession", "Beruf", "Métier", "Profesión", "Профессия", "专业", "專業" },
    priceAge = { "경매장 시세: %s", "Auction prices: %s", "Auktionspreise: %s", "Prix HV : %s", "Precios de subasta: %s", "Цены аукциона: %s", "拍卖行价格：%s", "拍賣場價格：%s" },
    priceNone = {
        "경매장 시세 없음 · 경매장을 열고 [시세 읽기]",
        "No auction prices · open the auction house and [Read prices]",
        "Keine Auktionspreise · Auktionshaus öffnen und [Preise lesen]",
        "Aucun prix HV · ouvrez l'hôtel des ventes et [Lire les prix]",
        "Sin precios · abre la casa de subastas y [Leer precios]",
        "Нет цен · откройте аукцион и [Считать цены]",
        "没有拍卖价格 · 打开拍卖行后点 [读取价格]",
        "沒有拍賣價格 · 開啟拍賣場後點 [讀取價格]",
    },
    scan = { "시세 읽기", "Read prices", "Preise lesen", "Lire les prix", "Leer precios", "Считать цены", "读取价格", "讀取價格" },
    scanTip = {
        "경매장을 연 상태에서 재료 시세를 읽습니다.",
        "Reads the material prices while the auction house is open.",
        "Liest die Materialpreise bei geöffnetem Auktionshaus.",
        "Lit le prix des composants quand l'hôtel des ventes est ouvert.",
        "Lee los precios de materiales con la casa de subastas abierta.",
        "Считывает цены материалов при открытом аукционе.",
        "在拍卖行打开时读取材料价格。",
        "在拍賣場開啟時讀取材料價格。",
    },
    scanClosed = { "경매장을 연 상태에서 누르세요.", "Open the auction house first.", "Öffne zuerst das Auktionshaus.", "Ouvrez d'abord l'hôtel des ventes.", "Abre primero la casa de subastas.", "Сначала откройте аукцион.", "请先打开拍卖行。", "請先開啟拍賣場。" },
    scanStarted = { "경매장 시세를 읽는 중입니다…", "Reading auction prices…", "Lese Auktionspreise…", "Lecture des prix…", "Leyendo precios…", "Считываю цены…", "正在读取拍卖价格…", "正在讀取拍賣價格…" },
    ago = { "%s 전", "%s ago", "vor %s", "il y a %s", "hace %s", "%s назад", "%s前", "%s前" },
    now = { "방금", "just now", "gerade eben", "à l'instant", "ahora", "только что", "刚刚", "剛剛" },
    unitMin = { "%d분", "%d min", "%d Min.", "%d min", "%d min", "%d мин", "%d分钟", "%d分鐘" },
    unitHour = { "%d시간", "%d h", "%d Std.", "%d h", "%d h", "%d ч", "%d小时", "%d小時" },
    unitDay = { "%d일", "%d d", "%d T.", "%d j", "%d d", "%d д", "%d天", "%d天" },
    summary = { "예상 제작 %d번 · 경매장 %s · 상점 %s", "About %d crafts · auction %s · vendor %s", "Etwa %d Herstellungen · Auktion %s · Händler %s", "Environ %d fabrications · HV %s · marchand %s", "Unas %d fabricaciones · subasta %s · vendedor %s", "Около %d изготовлений · аукцион %s · торговец %s", "约 %d 次制作 · 拍卖 %s · 商人 %s", "約 %d 次製作 · 拍賣 %s · 商人 %s" },
    saved = { " · 보유 재료로 %s 아낌", " · bags save %s", " · Taschen sparen %s", " · sacs : %s économisés", " · bolsas ahorran %s", " · запасы экономят %s", " · 已有材料省 %s", " · 已有材料省 %s" },
    steps = { "단계", "Steps", "Schritte", "Étapes", "Pasos", "Шаги", "步骤", "步驟" },
    shopping = { "장보기", "Shopping list", "Einkaufsliste", "Liste de courses", "Lista de compra", "Список покупок", "购物清单", "購物清單" },
    learnTag = { "배우기", "learn", "lernen", "apprendre", "aprender", "изучить", "学习", "學習" },
    obtainTag = { "도안 구하기", "get recipe", "Rezept besorgen", "obtenir la recette", "conseguir receta", "добыть рецепт", "获取配方", "取得配方" },
    obtainTip = {
        "상급자에게 배울 제조법으로는 오르지 않는 구간이라, 상점·드롭 도안을 구해야 합니다.",
        "No trainer recipe gives skill here: this recipe comes from a vendor or a drop.",
        "Hier gibt kein Lehrer-Rezept Punkte: Rezept vom Händler oder als Beute.",
        "Aucune recette de maître ne monte ici : recette de marchand ou de butin.",
        "Ninguna receta del instructor sube aquí: receta de vendedor o botín.",
        "Здесь рецепты учителя не дают навыка: рецепт у торговца или с добычи.",
        "此段训练师配方无法提升：需从商人或掉落获取配方。",
        "此段訓練師配方無法提升：需從商人或掉落取得配方。",
    },
    train = {
        "%d: 상급자에게서 다음 단계 배우기",
        "%d: train the next rank",
        "%d: nächsten Rang beim Lehrer lernen",
        "%d : apprendre le rang suivant",
        "%d: aprende el siguiente rango",
        "%d: изучите следующий ранг",
        "%d：向训练师学习下一级",
        "%d：向訓練師學習下一級",
    },
    gap = { "%d-%d: 오를 제조법 없음", "%d-%d: no recipe gives skill", "%d-%d: kein Rezept gibt Punkte", "%d-%d : aucune recette", "%d-%d: ninguna receta sube", "%d-%d: нет рецептов", "%d-%d：没有可升级的配方", "%d-%d：沒有可升級的配方" },
    learnProf = {
        "먼저 상급자에게서 전문 기술을 배우세요.",
        "Learn the profession from a trainer first.",
        "Lerne den Beruf zuerst bei einem Lehrer.",
        "Apprenez d'abord le métier auprès d'un maître.",
        "Aprende primero la profesión con un instructor.",
        "Сначала изучите профессию у учителя.",
        "请先向训练师学习这个专业。",
        "請先向訓練師學習這個專業。",
    },
    done = { "목표 숙련도에 도달했습니다.", "Target skill reached.", "Ziel erreicht.", "Objectif atteint.", "Objetivo alcanzado.", "Цель достигнута.", "已达到目标技能。", "已達到目標技能。" },
    gather = {
        "채집으로 오르는 기술입니다. 캐거나 낚으면서 올리세요.",
        "This skill rises by gathering: gather or fish to raise it.",
        "Diese Fertigkeit steigt beim Sammeln.",
        "Cette compétence monte en récoltant.",
        "Esta habilidad sube recolectando.",
        "Этот навык растёт при сборе.",
        "这个技能靠采集提升。",
        "這個技能靠採集提升。",
    },
    miningNote = {
        "채광은 캐면서도 오릅니다. 아래는 제련으로 올리는 길입니다.",
        "Mining also rises by mining; below is the way by smelting.",
        "Bergbau steigt auch beim Abbauen; unten der Weg über Verhütten.",
        "Le minage monte aussi en minant ; ci-dessous, par la fonte.",
        "La minería también sube minando; abajo, fundiendo.",
        "Горное дело растёт и при добыче; ниже — через плавку.",
        "采矿在采矿时也会提升；下面是靠熔炼的路线。",
        "採礦在採礦時也會提升；下面是靠熔煉的路線。",
    },
    -- step detail line
    turns = { "%s %d부터", "%s from %d", "%s ab %d", "%s dès %d", "%s desde %d", "%s с %d", "%s 自 %d 起", "%s 自 %d 起" },
    canNow = { "지금 %d번 가능", "%d now", "jetzt %d", "%d maintenant", "%d ahora", "сейчас %d", "现在可做 %d 次", "現在可做 %d 次" },
    chanceRange = { "확률 %d%%→%d%%", "chance %d%%→%d%%", "Chance %d%%→%d%%", "chance %d%%→%d%%", "prob. %d%%→%d%%", "шанс %d%%→%d%%", "几率 %d%%→%d%%", "機率 %d%%→%d%%" },
    orange = { "주황", "orange", "orange", "orange", "naranja", "оранжевый", "橙色", "橙色" },
    yellow = { "노랑", "yellow", "gelb", "jaune", "amarillo", "жёлтый", "黄色", "黃色" },
    green = { "초록", "green", "grün", "vert", "verde", "зелёный", "绿色", "綠色" },
    grey = { "회색", "grey", "grau", "gris", "gris", "серый", "灰色", "灰色" },
    -- shopping list groups
    grpMake = { "직접 만들기", "Make", "Herstellen", "À fabriquer", "Fabricar", "Сделать", "自己制作", "自己製作" },
    grpAuction = { "경매장에서 사기", "Buy at the auction house", "Im Auktionshaus kaufen", "Acheter à l'HV", "Comprar en subasta", "Купить на аукционе", "在拍卖行购买", "在拍賣場購買" },
    grpVendor = { "상점에서 사기", "Buy from vendors", "Beim Händler kaufen", "Acheter au marchand", "Comprar al vendedor", "Купить у торговца", "向商人购买", "向商人購買" },
    grpUnknown = { "시세 없음 (직접 구하기)", "No price (get them yourself)", "Kein Preis (selbst besorgen)", "Sans prix (à récolter)", "Sin precio (consíguelos)", "Нет цены (добыть самому)", "无价格（自行获取）", "無價格（自行取得）" },
    grpEnough = { "가방·은행에 충분함", "Enough in bags and bank", "Genug in Taschen und Bank", "Assez dans sacs et banque", "Suficiente en bolsas y banco", "Хватает в сумках и банке", "背包和银行里足够", "背包和銀行裡足夠" },
    makeN = { "%d번 만들기", "make %d", "%d herstellen", "fabriquer %d", "fabricar %d", "сделать %d", "制作 %d 次", "製作 %d 次" },
    countHave = { "%d개 (보유 %d)", "%d (have %d)", "%d (hast %d)", "%d (avez %d)", "%d (tienes %d)", "%d (есть %d)", "%d 个（已有 %d）", "%d 個（已有 %d）" },
    needHave = { "필요 %d · 보유 %d", "need %d · have %d", "benötigt %d · hast %d", "besoin %d · avez %d", "necesitas %d · tienes %d", "нужно %d · есть %d", "需要 %d · 已有 %d", "需要 %d · 已有 %d" },
    each = { "개당 %s", "%s each", "je %s", "%s pièce", "%s c/u", "%s за шт.", "单价 %s", "單價 %s" },
    countN = { "%d개", "%d", "%d", "%d", "%d", "%d", "%d 个", "%d 個" },
    noPrice = { "시세 없음", "no price", "kein Preis", "sans prix", "sin precio", "нет цены", "无价格", "無價格" },
    vendor = { "상점", "vendor", "Händler", "marchand", "vendedor", "торговец", "商人", "商人" },
    auction = { "경매장", "auction", "Auktion", "HV", "subasta", "аукцион", "拍卖", "拍賣" },
    total = { "합계 %s", "Total %s", "Summe %s", "Total %s", "Total %s", "Итого %s", "合计 %s", "合計 %s" },
    totalUnknown = { "합계 %s (시세 없는 재료 %d개 빼고)", "Total %s (%d without a price left out)", "Summe %s (%d ohne Preis nicht gezählt)", "Total %s (%d sans prix non comptés)", "Total %s (%d sin precio no incluidos)", "Итого %s (%d без цены не учтены)", "合计 %s（%d 种无价格未计）", "合計 %s（%d 種無價格未計）" },
    next = { "다음: %s ×%d 고르기", "Next: pick %s ×%d", "Weiter: %s ×%d wählen", "Suivant : %s ×%d", "Siguiente: %s ×%d", "Далее: %s ×%d", "下一步：选择 %s ×%d", "下一步：選擇 %s ×%d" },
    nextNone = { "고를 제조법 없음", "Nothing to pick", "Nichts zu wählen", "Rien à choisir", "Nada que elegir", "Нечего выбрать", "没有可选配方", "沒有可選配方" },
    nextTip = {
        "전문 기술 창에서 이 제조법을 고르고 만들 개수를 채웁니다.",
        "Picks this recipe in the profession window and fills in the count.",
        "Wählt das Rezept im Berufsfenster und trägt die Anzahl ein.",
        "Sélectionne la recette dans la fenêtre de métier et remplit la quantité.",
        "Elige la receta en la ventana de profesión y rellena la cantidad.",
        "Выбирает рецепт в окне профессии и вписывает количество.",
        "在专业窗口中选择该配方并填入数量。",
        "在專業視窗中選擇該配方並填入數量。",
    },
    needLearn = {
        "%s 은(는) 아직 배우지 않았습니다. %s",
        "%s is not learned yet. %s",
        "%s ist noch nicht erlernt. %s",
        "%s n'est pas encore apprise. %s",
        "%s aún no está aprendida. %s",
        "%s ещё не изучен. %s",
        "尚未学会 %s。%s",
        "尚未學會 %s。%s",
    },
    openWindow = {
        "전문 기술 창을 열면 고를 수 있습니다.",
        "Open the profession window to pick it.",
        "Öffne das Berufsfenster, um es zu wählen.",
        "Ouvrez la fenêtre de métier pour la choisir.",
        "Abre la ventana de profesión para elegirla.",
        "Откройте окно профессии, чтобы выбрать.",
        "打开专业窗口后即可选择。",
        "開啟專業視窗後即可選擇。",
    },
    padSelf = {
        "게임패드 모드에서는 전문 기술 창에서 직접 고르세요.",
        "With the gamepad on, pick it in the profession window yourself.",
        "Mit Gamepad bitte selbst im Berufsfenster wählen.",
        "Avec la manette, choisissez-la vous-même.",
        "Con el mando, elígela tú mismo.",
        "С геймпадом выберите сами в окне профессии.",
        "手柄模式下请在专业窗口中自行选择。",
        "手把模式下請在專業視窗中自行選擇。",
    },
    -- tooltips
    tipRange = { "숙련 %d-%d · 약 %d개", "Skill %d-%d · about %d crafts", "Fertigkeit %d-%d · etwa %d", "Compétence %d-%d · environ %d", "Habilidad %d-%d · unas %d", "Навык %d-%d · около %d", "技能 %d-%d · 约 %d 次", "技能 %d-%d · 約 %d 次" },
    tipChance = { "오를 확률 %d%% → %d%%", "Skill-up chance %d%% → %d%%", "Chance %d%% → %d%%", "Chance %d%% → %d%%", "Probabilidad %d%% → %d%%", "Шанс %d%% → %d%%", "提升几率 %d%% → %d%%", "提升機率 %d%% → %d%%" },
    tipCost = { "예상 비용 %s", "Expected cost %s", "Erwartete Kosten %s", "Coût prévu %s", "Coste previsto %s", "Ожидаемая цена %s", "预计花费 %s", "預計花費 %s" },
    tipPer = { "한 번에 드는 재료", "Materials per craft", "Material pro Herstellung", "Composants par fabrication", "Materiales por fabricación", "Материалы за раз", "每次所需材料", "每次所需材料" },
    tipStepMats = { "이 단계 재료 (보유)", "Materials for this step (have)", "Material für diesen Schritt (hast)", "Composants de l'étape (avez)", "Materiales del paso (tienes)", "Материалы шага (есть)", "本步骤材料（已有）", "本步驟材料（已有）" },
    tipReuse = { "앞 단계에서 만든 것 %d개 사용", "Uses %d made in an earlier step", "Nutzt %d aus einem früheren Schritt", "Utilise %d d'une étape précédente", "Usa %d de un paso anterior", "Использует %d из прошлого шага", "使用之前步骤做出的 %d 个", "使用之前步驟做出的 %d 個" },
    tipLearnAt = { "배우는 곳", "Learn from", "Lernen bei", "Apprendre auprès de", "Aprender de", "Где изучить", "学习地点", "學習地點" },
    tipClick = {
        "클릭: 전문 기술 창에서 고르기 · Shift+클릭: 링크 · 오른쪽 클릭: 배우는 곳 지도에서 찾기",
        "Click: pick in the profession window · Shift-click: link · Right-click: where to learn on the map",
        "Klick: im Berufsfenster wählen · Umschalt-Klick: Link · Rechtsklick: Lernort auf der Karte",
        "Clic : choisir dans la fenêtre · Maj-clic : lien · Clic droit : où l'apprendre sur la carte",
        "Clic: elegir en la ventana · Mayús-clic: enlace · Clic derecho: dónde aprender en el mapa",
        "Щелчок: выбрать в окне · Shift-щелчок: ссылка · Правый щелчок: где изучить на карте",
        "点击：在专业窗口中选择 · Shift+点击：链接 · 右键：在地图上查找学习地点",
        "點擊：在專業視窗中選擇 · Shift+點擊：連結 · 右鍵：在地圖上查找學習地點",
    },
    tipNeed = { "필요 %d · 보유 %d · 살 것 %d", "Need %d · have %d · buy %d", "Benötigt %d · hast %d · kaufen %d", "Besoin %d · avez %d · acheter %d", "Necesitas %d · tienes %d · comprar %d", "Нужно %d · есть %d · купить %d", "需要 %d · 已有 %d · 购买 %d", "需要 %d · 已有 %d · 購買 %d" },
    tipItemPrice = { "단가 %s (%s)", "Unit price %s (%s)", "Stückpreis %s (%s)", "Prix unitaire %s (%s)", "Precio unidad %s (%s)", "Цена за шт. %s (%s)", "单价 %s（%s）", "單價 %s（%s）" },
    tipAuctionAt = { "경매장 시세 %s", "Auction price %s", "Auktionspreis %s", "Prix HV %s", "Precio de subasta %s", "Цена аукциона %s", "拍卖价格 %s", "拍賣價格 %s" },
    tipUses = { "쓰이는 단계", "Used in", "Verwendet in", "Utilisé dans", "Se usa en", "Используется в", "用于", "用於" },
    tipSellers = { "파는 곳 (게임에서 확인)", "Sold by (seen in the game)", "Verkauft von (im Spiel gesehen)", "Vendu par (vu en jeu)", "Lo vende (visto en el juego)", "Продаёт (замечено в игре)", "出售者（游戏中确认）", "販售者（遊戲中確認）" },
    tipFindMap = {
        "오른쪽 클릭: 지도에서 찾기",
        "Right-click: find on the map",
        "Rechtsklick: auf der Karte suchen",
        "Clic droit : chercher sur la carte",
        "Clic derecho: buscar en el mapa",
        "Правый щелчок: найти на карте",
        "右键：在地图上查找",
        "右鍵：在地圖上查找",
    },
}

local function T(key, ...)
    local row = TEXT[key]
    if not row then return key end
    local text = row[LANGS[ns.ACTIVE_LANG] or 2] or row[2]
    if select("#", ...) > 0 then
        local ok, out = pcall(string.format, text, ...)
        return ok and out or text
    end
    return text
end
ns.LevelingText = T

-----------------------------------------------------------------------------
-- Helpers
-----------------------------------------------------------------------------
local function money(copper)
    copper = floor((tonumber(copper) or 0) + 0.5)
    if copper >= 10000 then copper = floor(copper / 100 + 0.5) * 100 end   -- copper hidden above a gold
    if GetCoinTextureString then
        local ok, text = pcall(GetCoinTextureString, copper)
        if ok and type(text) == "string" and text ~= "" then return text end
    end
    local g, s, c = floor(copper / 10000), floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "|cffffd100g|r" end
    if s > 0 then parts[#parts + 1] = s .. "|cffc7c7cfs|r" end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "|cffeda55fc|r" end
    return table.concat(parts, " ")
end

local function age(at)
    local now = (GetServerTime and GetServerTime()) or time()
    local d = max(0, now - (tonumber(at) or now))
    if d < 60 then return T("now") end
    local span
    if d < 3600 then span = T("unitMin", floor(d / 60))
    elseif d < 86400 then span = T("unitHour", floor(d / 3600))
    else span = T("unitDay", floor(d / 86400)) end
    return T("ago", span)
end

local COLOR_HEX = { orange = "ff8040", yellow = "ffff00", green = "40bf40", grey = "808080", red = "ff2020" }
local COLOR_RGB = { orange = { 1, 0.5, 0.25 }, yellow = { 1, 1, 0 }, green = { 0.25, 0.75, 0.25 }, grey = { 0.5, 0.5, 0.5 } }
local MUTED = "|cffa7b9c5"
local CYAN = "|cff4bc8e8"

local function recipeName(r) return ns.GetLocalizedRecipeName and ns.GetLocalizedRecipeName(r) or tostring(r[R_SPELL]) end
local function itemName(id) return ns.ItemName and ns.ItemName(id) or ("#" .. tostring(id)) end
local function itemIcon(id) return ns.ItemIcon and ns.ItemIcon(id) or 134400 end
local function iconText(id, size) return "|T" .. tostring(itemIcon(id)) .. ":" .. (size or 12) .. ":" .. (size or 12) .. ":0:0|t" end
local function recipeIcon(r) return ns.ResolveRecipeDisplayIcon and ns.ResolveRecipeDisplayIcon(r) or 134400 end
local function colorWord(c) return "|cff" .. (COLOR_HEX[c] or "ffffff") .. T(c) .. "|r" end
local function pct(p) return floor((tonumber(p) or 0) * 100 + 0.5) end
local function padOn() return ns.GamePad and ns.GamePad.IsActive and ns.GamePad.IsActive() and true or false end
local function browser() return ns.RecipeBrowserWindow or {} end
local function flatButton(parent, w, h, accent, onClick)
    return browser().createRecipeFlatButton(parent, w, h, accent, onClick)
end

-- crafts the bags and bank allow now (nil: the recipe needs nothing)
local function craftableNow(r)
    local n
    for _, re in ipairs(r[R_REAG] or {}) do
        local can = floor(Leveling.Owned(re[1]) / max(1, re[2]))
        n = n and min(n, can) or can
    end
    return n
end

-- names of the NPCs other EzWoW users saw selling an item (shared records)
local function sellersOf(item)
    local share = ns.Share
    if not (share and type(share.GetVendors) == "function" and type(share.SourceName) == "function") then return nil end
    local ok, vendors = pcall(share.GetVendors, item)
    if not ok or type(vendors) ~= "table" then return nil end
    local names, seen = {}, {}
    for _, npcID in ipairs(vendors) do
        local other = false
        if type(share.IsOtherSide) == "function" then
            local okSide, res = pcall(share.IsOtherSide, npcID)
            other = okSide and res == true
        end
        local okName, n = pcall(share.SourceName, "n" .. npcID, ns.ACTIVE_LANG)
        if not other and okName and type(n) == "string" and n ~= "" and not seen[n] then
            seen[n] = true
            names[#names + 1] = n
            if #names >= 4 then break end
        end
    end
    return #names > 0 and table.concat(names, ", ") or nil
end

-----------------------------------------------------------------------------
-- Window
-----------------------------------------------------------------------------
local Panel = ns.LevelingPanel or {}
ns.LevelingPanel = Panel
local frame
local state = { prof = nil, plan = nil, rank = nil, maxRank = nil, stepOffset = 0, shopOffset = 0, lines = {}, shopLines = {} }
local W, ROW_H, MAX_ROWS = 460, 18, 40
local HEADER_H = 30

function Panel.IsShown() return frame and frame:IsShown() or false end

local function makeRow(parent, onClick, onEnter)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row.cur = row:CreateTexture(nil, "BACKGROUND")
    row.cur:SetAllPoints()
    row.cur:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.18)
    row.cur:Hide()
    row.head = row:CreateTexture(nil, "BACKGROUND")
    row.head:SetAllPoints()
    row.head:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.10)
    row.head:Hide()
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.bar = row:CreateTexture(nil, "ARTWORK")
    row.bar:SetPoint("TOPLEFT", 0, 0)
    row.bar:SetPoint("BOTTOMLEFT", 0, 0)
    row.bar:SetWidth(3)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(15, 15)
    row.icon:SetPoint("LEFT", 6, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.right:SetPoint("RIGHT", -4, 0)
    row.right:SetJustifyH("RIGHT")
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", onClick)
    row:SetScript("OnEnter", onEnter)
    row:SetScript("OnLeave", GameTooltip_Hide)
    return row
end

-- text starts after the icon, or further in for detail lines
local function placeText(row, indent)
    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", row, "LEFT", indent, 0)
    row.text:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
end

local function makeBox(parent)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    ns.UIKit:ApplyBackdrop(box)
    box:SetBackdropColor(unpack(Theme.bgSub))
    box:SetBackdropBorderColor(unpack(Theme.border))
    box:EnableMouseWheel(true)
    if box.SetClipsChildren then box:SetClipsChildren(true) end
    box.rows = {}
    return box
end

local function addTag(tip)
    tip:AddDoubleLine(" ", "EzWoW - Profession Recipes", 0, 0, 0, 0.5, 0.5, 0.5)
    tip:Show()
    if _G.EzWoWTooltipTagSizer and _G.EzWoWTooltipTagSizer.Refit then pcall(_G.EzWoWTooltipTagSizer.Refit, tip) end
end

-- crafts still needed in a step from the current skill on
local function remainingCrafts(st)
    if not st or not st.recipe then return 0 end
    local rank = state.rank or st.from
    if rank < st.from or rank >= st.to then return st.crafts or 0 end
    local sum = 0
    for s = rank, st.to - 1 do
        local p = Leveling.Chance(st.recipe, s)
        if p > 0 then sum = sum + 1 / p end
    end
    return max(1, math.ceil(sum - 1e-6))
end

local function currentStep()
    local plan = state.plan
    if not plan then return nil end
    local rank = state.rank
    for _, st in ipairs(plan.steps) do
        if st.recipe and rank and rank >= st.from and rank < st.to then return st end
    end
    for _, st in ipairs(plan.steps) do
        if st.recipe then return st end
    end
    return nil
end

-- picks the recipe in the profession window and fills in the count
function Panel.Select(st)
    if not st or not st.recipe then return end
    local r = st.recipe
    if st.kind ~= "learned" then
        local src = ns.GetLocalizedRecipeSourceText and ns.GetLocalizedRecipeSourceText(r) or ""
        print(PREFIX .. T("needLearn", recipeName(r), src))
        return
    end
    if padOn() then print(PREFIX .. T("padSelf")) return end
    local host = _G.ProfessionsFrame
    if not (host and host:IsShown()) then print(PREFIX .. T("openWindow")) return end
    local id, count = r[R_SPELL], remainingCrafts(st)
    local page = host.CraftingPage
    local list = page and page.RecipeList
    local done = false
    if C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo and list and list.SelectRecipe then
        local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, id)
        if ok and type(info) == "table" then done = pcall(list.SelectRecipe, list, info, true) end
    end
    if not done and C_TradeSkillUI and C_TradeSkillUI.OpenRecipe then done = pcall(C_TradeSkillUI.OpenRecipe, id) end
    if not done then print(PREFIX .. T("openWindow")) return end
    if count > 0 then
        C_Timer.After(0.15, function()
            local box = page and page.CreateMultipleInputBox
            if box and box.SetValue then pcall(box.SetValue, box, count) end
        end)
    end
end

local function lineItem(line)
    return line and (line.buy and line.buy.item or line.make and line.make.item) or nil
end

local function onStepClick(self, button)
    local line = self.line
    local st = line and line.step
    if not st or not st.recipe then return end
    if IsModifiedClick and IsModifiedClick("CHATLINK") and browser().linkRecipe then
        browser().linkRecipe(st.recipe, st.recipe[R_ITEM])
        return
    end
    if button == "RightButton" then
        if browser().findRecipeOnMap then browser().findRecipeOnMap(st.recipe) end
        return
    end
    Panel.Select(st)
end

local function onStepEnter(self)
    local line = self.line
    local st = line and line.step
    if not st or not st.recipe then return end
    local r = st.recipe
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(recipeName(r), unpack(Theme.accent))
    GameTooltip:AddLine(T("tipRange", st.from, st.to, st.crafts or 0), 0.93, 0.96, 0.97)
    GameTooltip:AddLine(T("tipChance", pct(st.chance), pct(st.lastChance or st.chance)), 0.93, 0.96, 0.97)
    local segs = {}
    for _, seg in ipairs(st.segments or {}) do
        segs[#segs + 1] = colorWord(seg.color) .. " " .. seg.from .. "-" .. seg.to
    end
    if #segs > 0 then GameTooltip:AddLine(table.concat(segs, "  "), 1, 1, 1) end
    GameTooltip:AddLine(T("tipCost", st.unknown and T("noPrice") or money(st.cost)), 0.93, 0.96, 0.97)
    if st.kind ~= "learned" then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(T("tipLearnAt"), unpack(Theme.accent))
        if st.kind == "other" then GameTooltip:AddLine(T("obtainTip"), 1, 0.82, 0, true) end
        local src = ns.GetLocalizedRecipeSourceText and ns.GetLocalizedRecipeSourceText(r) or ""
        if src ~= "" then GameTooltip:AddLine(src, 0.93, 0.96, 0.97, true) end
        if browser().sharedSourceText then
            local ok, seen = pcall(browser().sharedSourceText, r)
            if ok and type(seen) == "string" then GameTooltip:AddLine(seen, 0.93, 0.96, 0.97, true) end
        end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(T("tipPer"), unpack(Theme.accent))
    for _, re in ipairs(r[R_REAG] or {}) do
        local unit = Prices.Unit(re[1])
        GameTooltip:AddDoubleLine(iconText(re[1], 14) .. " " .. itemName(re[1]) .. " ×" .. re[2],
            unit and money(unit * re[2]) or T("noPrice"), 0.93, 0.96, 0.97, 0.93, 0.96, 0.97)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(T("tipStepMats"), unpack(Theme.accent))
    for _, re in ipairs(r[R_REAG] or {}) do
        GameTooltip:AddDoubleLine(iconText(re[1], 14) .. " " .. itemName(re[1]) .. " ×" .. (re[2] * (st.crafts or 0)),
            tostring(Leveling.Owned(re[1])), 0.93, 0.96, 0.97, 0.66, 0.73, 0.77)
    end
    if st.reuse then
        for item, n in pairs(st.reuse) do
            GameTooltip:AddLine(T("tipReuse", n) .. ": " .. itemName(item), 0.29, 0.78, 0.91, true)
        end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(T("tipClick"), 0.29, 0.78, 0.91, true)
    addTag(GameTooltip)
end

local function onShopClick(self, button)
    local item = lineItem(self.line)
    if not item then return end
    if IsModifiedClick and IsModifiedClick("CHATLINK") and browser().linkRecipe then
        browser().linkRecipe(nil, item)
        return
    end
    if button == "RightButton" and browser().launchInMapFinder then
        browser().launchInMapFinder(itemName(item))
    end
end

local function stepsText(steps)
    local names = {}
    for _, st in ipairs(steps or {}) do
        if st.recipe then names[#names + 1] = st.from .. "-" .. st.to .. " " .. recipeName(st.recipe) end
        if #names >= 4 then break end
    end
    for _, m in ipairs(steps and steps.made or {}) do
        names[#names + 1] = T("makeN", m.crafts) .. ": " .. itemName(m.item)
    end
    return table.concat(names, "\n")
end

local function onShopEnter(self)
    local line = self.line
    local item = lineItem(line)
    if not item then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    pcall(GameTooltip.SetItemByID, GameTooltip, item)
    GameTooltip:AddLine(" ")
    local row = line.buy or line.make
    if line.buy then
        GameTooltip:AddLine(T("tipNeed", row.need, row.have, row.buy), 0.93, 0.96, 0.97)
    else
        GameTooltip:AddLine(T("needHave", row.need, row.have) .. " · " .. T("makeN", row.crafts), 0.93, 0.96, 0.97)
    end
    local unit, src = Prices.Unit(item)
    if unit then
        GameTooltip:AddLine(T("tipItemPrice", money(unit), src == "vendor" and T("vendor") or T("auction")), 0.93, 0.96, 0.97)
    end
    local ah, at = Prices.Auction(item)
    if ah and at and at > 0 then GameTooltip:AddLine(T("tipAuctionAt", money(ah)) .. " · " .. age(at), 0.66, 0.73, 0.77) end
    local sellers = (Prices.Vendor(item) or line.buy and line.buy.source == "vendor") and sellersOf(item)
    if sellers then
        GameTooltip:AddLine(T("tipSellers") .. ": " .. sellers, 0.67, 0.89, 0.42, true)
    end
    local uses = stepsText(row.steps)
    if uses ~= "" then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(T("tipUses"), unpack(Theme.accent))
        GameTooltip:AddLine(uses, 0.93, 0.96, 0.97, true)
    end
    if SlashCmdList and SlashCmdList.EZWOWMAPFINDER then GameTooltip:AddLine(T("tipFindMap"), 0.29, 0.78, 0.91) end
    addTag(GameTooltip)
end

-----------------------------------------------------------------------------
-- Display lines
-----------------------------------------------------------------------------
-- one detail line under a step: the materials of one craft, where it turns
-- yellow / green, how many the bags allow now
local function stepDetail(st)
    local parts = {}
    local per = {}
    for _, re in ipairs(st.recipe[R_REAG] or {}) do
        per[#per + 1] = iconText(re[1]) .. itemName(re[1]) .. "×" .. re[2]
    end
    if #per > 0 then parts[#parts + 1] = table.concat(per, " ") end
    for i = 2, #(st.segments or {}) do
        local seg = st.segments[i]
        parts[#parts + 1] = T("turns", colorWord(seg.color), seg.from)
    end
    local now = craftableNow(st.recipe)
    if now then parts[#parts + 1] = T("canNow", now) end
    return table.concat(parts, "  ·  ")
end

local function buildLines(plan, notes)
    local lines = {}
    for _, msg in ipairs(notes) do lines[#lines + 1] = { msg = msg } end
    for _, st in ipairs(plan and plan.steps or {}) do
        if st.recipe then
            lines[#lines + 1] = { step = st }
            lines[#lines + 1] = { step = st, detail = true }
        else
            lines[#lines + 1] = { note = st }
        end
    end
    return lines
end

local function buildShopLines(plan)
    local lines = {}
    if not plan then return lines end
    local groups = {
        { key = "grpMake", rows = {} }, { key = "grpAuction", rows = {}, total = plan.byAuction },
        { key = "grpVendor", rows = {}, total = plan.byVendor }, { key = "grpUnknown", rows = {} },
        { key = "grpEnough", rows = {} },
    }
    for _, m in ipairs(plan.make) do table.insert(groups[1].rows, { make = m }) end
    for _, b in ipairs(plan.buy) do
        local g
        if b.buy <= 0 then g = groups[5]
        elseif not b.unit then g = groups[4]
        elseif b.source == "vendor" then g = groups[3]
        else g = groups[2] end
        table.insert(g.rows, { buy = b })
    end
    for _, g in ipairs(groups) do
        if #g.rows > 0 then
            lines[#lines + 1] = { header = g.key, total = g.total, count = #g.rows }
            for _, row in ipairs(g.rows) do lines[#lines + 1] = row end
        end
    end
    return lines
end

-----------------------------------------------------------------------------
-- Drawing
-----------------------------------------------------------------------------
local function visibleRows(box)
    local h = box:GetHeight() or 0
    return max(1, min(MAX_ROWS, floor((h - 6) / ROW_H)))
end

local function ensureRows(box, count, onClick, onEnter)
    for i = #box.rows + 1, count do
        local row = makeRow(box, onClick, onEnter)
        row:SetPoint("TOPLEFT", box, "TOPLEFT", 3, -3 - (i - 1) * ROW_H)
        row:SetPoint("RIGHT", box, "RIGHT", -3, 0)
        box.rows[i] = row
    end
end

local function drawSteps()
    local box = frame.stepsBox
    local n = visibleRows(box)
    ensureRows(box, n, onStepClick, onStepEnter)
    local lines = state.lines
    state.stepOffset = max(0, min(state.stepOffset, #lines - n))
    local cur = currentStep()
    for i, row in ipairs(box.rows) do
        local line = (i <= n) and lines[state.stepOffset + i] or nil
        row.line = line
        row.cur:Hide()
        row.head:Hide()
        row.bar:Hide()
        row.icon:Hide()
        if not line then
            row:Hide()
        else
            row:Show()
            local st = line.step
            if st and st.recipe then
                local color = COLOR_RGB[st.color] or COLOR_RGB.orange
                row.bar:SetColorTexture(color[1], color[2], color[3], line.detail and 0.35 or 0.9)
                row.bar:Show()
                if st == cur then row.cur:Show() end
                if line.detail then
                    placeText(row, 26)
                    row.text:SetText(MUTED .. stepDetail(st) .. "|r")
                    row.right:SetText(MUTED .. T("chanceRange", pct(st.chance), pct(st.lastChance or st.chance)) .. "|r")
                else
                    row.icon:SetTexture(recipeIcon(st.recipe))
                    row.icon:Show()
                    placeText(row, 26)
                    local name = "|cff" .. (COLOR_HEX[st.color] or "ffffff") .. recipeName(st.recipe) .. "|r"
                    if st.kind == "trainer" then
                        name = name .. "  " .. CYAN .. T("learnTag") .. "|r"
                    elseif st.kind == "other" then
                        name = name .. "  |cffffd100" .. T("obtainTag") .. "|r"
                    end
                    row.text:SetText(string.format("%d-%d  %s", st.from, st.to, name))
                    row.right:SetText("×" .. (st.crafts or 0) .. "  " .. (st.unknown and ("|cffff8040" .. T("noPrice") .. "|r") or money(st.cost)))
                end
            else
                placeText(row, 8)
                row.right:SetText("")
                local note = line.note
                if note and note.train then
                    row.text:SetText("|cffffd100" .. T("train", note.at) .. "|r")
                elseif note and note.gap then
                    row.text:SetText("|cff808080" .. T("gap", note.from, note.to) .. "|r")
                else
                    row.text:SetText(MUTED .. (line.msg or "") .. "|r")
                end
            end
        end
    end
end

local function drawShop()
    local box = frame.shopBox
    local n = visibleRows(box)
    ensureRows(box, n, onShopClick, onShopEnter)
    local lines = state.shopLines
    state.shopOffset = max(0, min(state.shopOffset, #lines - n))
    for i, row in ipairs(box.rows) do
        local line = (i <= n) and lines[state.shopOffset + i] or nil
        row.line = line
        row.cur:Hide()
        row.head:Hide()
        row.bar:Hide()
        row.icon:Hide()
        if not line then
            row:Hide()
        elseif line.header then
            row:Show()
            row.head:Show()
            placeText(row, 8)
            row.text:SetText("|cffeba86a" .. T(line.header) .. "|r")
            row.right:SetText(line.total and money(line.total) or (MUTED .. T("countN", line.count) .. "|r"))
        else
            row:Show()
            row.icon:Show()
            placeText(row, 26)
            if line.make then
                local m = line.make
                row.icon:SetTexture(itemIcon(m.item))
                row.text:SetText(itemName(m.item) .. "  " .. MUTED .. T("needHave", m.need, m.have) .. "|r")
                row.right:SetText(CYAN .. T("makeN", m.crafts) .. "|r")
            else
                local b = line.buy
                row.icon:SetTexture(itemIcon(b.item))
                local hex = ns.QualityHex and ns.QualityHex(b.item) or "|cffffffff"
                if b.buy <= 0 then
                    row.text:SetText(hex .. itemName(b.item) .. "|r  " .. MUTED .. T("needHave", b.need, b.have) .. "|r")
                    row.right:SetText("")
                elseif b.unit then
                    row.text:SetText(hex .. itemName(b.item) .. "|r  " .. MUTED .. T("countHave", b.buy, b.have) .. "|r")
                    row.right:SetText(MUTED .. T("each", money(b.unit)) .. "|r  " .. money(b.cost))
                else
                    row.text:SetText(hex .. itemName(b.item) .. "|r  " .. MUTED .. T("countHave", b.buy, b.have) .. "|r")
                    row.right:SetText("|cffff8040" .. T("noPrice") .. "|r")
                end
            end
        end
    end
end

local function drawSkillBar()
    local bar = frame.skillBar
    local rank, maxRank, target = state.rank, state.maxRank, state.target or Leveling.MAX_SKILL
    local top = Leveling.MAX_SKILL
    bar:SetMinMaxValues(0, top)
    bar:SetValue(rank or 0)
    local w = bar:GetWidth() or (W - 28)
    for i, tier in ipairs(Leveling.TIERS) do
        local mark = bar.marks[i]
        mark:ClearAllPoints()
        mark:SetPoint("TOP", bar, "TOPLEFT", w * tier / top, 0)
        mark:SetPoint("BOTTOM", bar, "BOTTOMLEFT", w * tier / top, 0)
    end
    bar.cap:SetShown(maxRank and maxRank > 0 and maxRank < top and true or false)
    if maxRank and maxRank > 0 then
        bar.cap:ClearAllPoints()
        bar.cap:SetPoint("TOP", bar, "TOPLEFT", w * maxRank / top, 2)
        bar.cap:SetPoint("BOTTOM", bar, "BOTTOMLEFT", w * maxRank / top, -2)
    end
    bar.goal:ClearAllPoints()
    bar.goal:SetPoint("TOP", bar, "TOPLEFT", w * target / top, 3)
    bar.goal:SetPoint("BOTTOM", bar, "BOTTOMLEFT", w * target / top, -3)
    if not rank then
        bar.text:SetText(T("notLearned", target))
    elseif maxRank and maxRank > 0 then
        bar.text:SetText(T("skillBar", rank, maxRank, target))
    else
        bar.text:SetText(T("skillBarNoCap", rank, target))
    end
end

function Panel.Draw()
    if not (frame and frame:IsShown()) then return end
    local prof = ns.PROF_BY_ID and ns.PROF_BY_ID[state.prof]
    local profName = prof and ns.GetLocalizedProfessionName(prof) or "?"
    frame.icon:SetTexture(prof and prof.icon or 134400)
    frame.title:SetText(T("title", profName))
    ns.UIKit:FitFontString(frame.title, W - 200, 1)
    drawSkillBar()
    frame.targetValue:SetText(tostring(state.target or "-"))
    frame.trainer:SetChecked(ns.DB.levelTrainer ~= false)
    local at, src = Prices.Status()
    if at then
        local who = (src == "tooltip" and " · EzWoW - Tooltip") or (src == "bags" and " · EzWoW - Bags") or ""
        frame.priceText:SetText(T("priceAge", age(at)) .. "|cff808080" .. who .. "|r")
    else
        frame.priceText:SetText(MUTED .. T("priceNone") .. "|r")
    end
    ns.UIKit:FitFontString(frame.priceText, W - 130, 1)
    frame.scanButton:SetAlpha(Prices.AuctionOpen() and 1 or 0.5)
    local plan = state.plan
    if plan and plan.totalCrafts > 0 then
        local text = T("summary", plan.totalCrafts, money(plan.byAuction), money(plan.byVendor))
        if plan.saved > 0 then text = text .. T("saved", money(plan.saved)) end
        frame.summary:SetText(MUTED .. text .. "|r")
    else
        frame.summary:SetText("")
    end
    ns.UIKit:FitFontString(frame.summary, W - 28, 1)
    drawSteps()
    drawShop()
    if plan and (#plan.buy > 0 or #plan.make > 0) then
        if #plan.unknown > 0 then
            frame.total:SetText(T("totalUnknown", money(plan.total), #plan.unknown))
        else
            frame.total:SetText(T("total", money(plan.total)))
        end
    else
        frame.total:SetText("")
    end
    local st = currentStep()
    if st then
        frame.nextButton:SetText(T("next", recipeName(st.recipe), remainingCrafts(st)))
        frame.nextButton:SetAlpha(1)
    else
        frame.nextButton:SetText(T("nextNone"))
        frame.nextButton:SetAlpha(0.5)
    end
    if ns.UpdateTabChecks then ns.UpdateTabChecks() end
end

-----------------------------------------------------------------------------
-- Planning
-----------------------------------------------------------------------------
-- the target starts at the highest skill (the training steps on the way are marked)
local function defaultTarget()
    return Leveling.MAX_SKILL
end

local function targetFor(prof, from)
    ns.DB.levelTarget = type(ns.DB.levelTarget) == "table" and ns.DB.levelTarget or {}
    local t = tonumber(ns.DB.levelTarget[prof])
    if not t or t <= from then t = defaultTarget() end
    return max(min(from + 1, Leveling.MAX_SKILL), min(Leveling.MAX_SKILL, t))
end

function Panel.Refresh()
    if not (frame and frame:IsShown()) then return end
    local prof = state.prof
    local data = prof and ns.Data and ns.Data[prof]
    state.lines, state.shopLines, state.plan = {}, {}, nil
    if not data then Panel.Draw() return end
    local rank, maxRank = Leveling.SkillOf(prof)
    state.rank, state.maxRank = rank, maxRank
    local from = rank or 1
    state.target = targetFor(prof, from)
    local notes = {}
    if Leveling.GATHERING[prof] then
        state.lines = buildLines(nil, { T("gather") })
        Panel.Draw()
        return
    end
    if not rank then notes[#notes + 1] = T("learnProf") end
    if prof == Leveling.MINING then notes[#notes + 1] = T("miningNote") end
    if from >= state.target then
        notes[#notes + 1] = T("done")
        state.lines = buildLines(nil, notes)
        Panel.Draw()
        return
    end
    local learned = Leveling.LearnedSet(prof)
    local plan = Leveling.BuildPlan(data.recipes, {
        from = from, to = state.target, maxRank = rank and maxRank or nil,
        usable = Leveling.UsableFn(learned, ns.DB.levelTrainer ~= false, true),
        price = Prices.Unit, owned = Leveling.Owned,
    })
    state.plan = plan
    state.lines = buildLines(plan, notes)
    state.shopLines = buildShopLines(plan)
    Panel.Draw()
end

local pending = false
function Panel.QueueRefresh()
    if pending or not (frame and frame:IsShown()) then return end
    pending = true
    C_Timer.After(0.3, function()
        pending = false
        Panel.Refresh()
    end)
end
Prices.OnChanged(Panel.QueueRefresh)

-----------------------------------------------------------------------------
-- Layout, docking
-----------------------------------------------------------------------------
local TOP = HEADER_H + 112

function Panel.Layout()
    if not frame then return end
    local h = frame:GetHeight() or 640
    local bottom = 64
    local avail = max(220, h - TOP - bottom)
    local stepsH = floor(avail * 0.48) - 18
    local shopH = avail - stepsH - 36
    frame.stepsLabel:ClearAllPoints()
    frame.stepsLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -TOP)
    frame.stepsBox:ClearAllPoints()
    frame.stepsBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -TOP - 16)
    frame.stepsBox:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
    frame.stepsBox:SetHeight(stepsH)
    frame.shopLabel:ClearAllPoints()
    frame.shopLabel:SetPoint("TOPLEFT", frame.stepsBox, "BOTTOMLEFT", 4, -6)
    frame.shopBox:ClearAllPoints()
    frame.shopBox:SetPoint("TOPLEFT", frame.stepsBox, "BOTTOMLEFT", 0, -22)
    frame.shopBox:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
    frame.shopBox:SetHeight(shopH)
end

-- right of the profession window, past any tabs on its right side
function Panel.Dock()
    local host = browser().resolveHostFrame and browser().resolveHostFrame()
    frame:ClearAllPoints()
    if host and host:IsShown() then
        frame.docked = true
        local right, offset = host:GetRight(), 2
        if right and browser().sideTabs then
            for _, tab in ipairs(browser().sideTabs()) do
                local l = tab:IsShown() and tab:GetLeft()
                local r = l and tab:GetRight()
                if l and r and l >= right - 12 then offset = max(offset, r - right + 2) end
            end
        end
        frame:SetPoint("TOPLEFT", host, "TOPRIGHT", offset, 0)
        local hostH = (host:GetHeight() or 640) * (host:GetEffectiveScale() or 1) / (frame:GetEffectiveScale() or 1)
        frame:SetHeight(max(520, min(780, hostH)))
    else
        frame.docked = false
        local pos = ns.DB.levelPos
        if type(pos) == "table" and pos[1] then
            frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
        else
            frame:SetPoint("CENTER", UIParent, "CENTER", 260, 0)
        end
        frame:SetHeight(640)
    end
    Panel.Layout()
end

-----------------------------------------------------------------------------
-- Profession menu
-----------------------------------------------------------------------------
local function showProfMenu(owner)
    local menu = frame.profMenu
    if menu:IsShown() then menu:Hide() return end
    for _, b in ipairs(menu.buttons) do b:Hide() end
    local list, ranks = {}, {}
    for _, p in ipairs(ns.PROFESSIONS or {}) do
        if ns.Data[p.id] and not Leveling.GATHERING[p.id] then
            list[#list + 1] = p
            ranks[p.id] = Leveling.SkillOf(p.id)
        end
    end
    table.sort(list, function(a, b)
        local la, lb = ranks[a.id] and 1 or 0, ranks[b.id] and 1 or 0
        if la ~= lb then return la > lb end
        return ns.GetLocalizedProfessionName(a) < ns.GetLocalizedProfessionName(b)
    end)
    for i, p in ipairs(list) do
        local b = menu.buttons[i]
        if not b then
            b = flatButton(menu, 170, 20, false)
            b:SetPoint("TOPLEFT", menu, "TOPLEFT", 6, -6 - (i - 1) * 22)
            menu.buttons[i] = b
        end
        local rank = ranks[p.id]
        b:SetText(rank and (ns.GetLocalizedProfessionName(p) .. "  " .. MUTED .. rank .. "|r")
            or ("|cff808080" .. ns.GetLocalizedProfessionName(p) .. "|r"))
        b:SetScript("OnClick", function()
            menu:Hide()
            state.prof, state.stepOffset, state.shopOffset = p.id, 0, 0
            Panel.Refresh()
        end)
        b:Show()
    end
    menu:SetSize(182, 12 + #list * 22)
    menu:ClearAllPoints()
    menu:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 0, -2)
    menu:Show()
end

-----------------------------------------------------------------------------
-- Build
-----------------------------------------------------------------------------
function Panel.Build()
    if frame then return frame end
    frame = CreateFrame("Frame", "EzWoWProfessionLevelingFrame", UIParent, "BackdropTemplate")
    frame:SetSize(W, 640)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:Hide()
    ns.UIKit:ApplyBackdrop(frame)
    frame:SetBackdropColor(unpack(Theme.bg))
    frame:SetBackdropBorderColor(unpack(Theme.border))
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) if not self.docked then self:StartMoving() end end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if not self.docked then
            local point, _, relPoint, x, y = self:GetPoint()
            ns.DB.levelPos = { point, relPoint, x, y }
        end
    end)

    -- header band (the EzWoW window look)
    local band = frame:CreateTexture(nil, "ARTWORK")
    band:SetPoint("TOPLEFT", 1, -1)
    band:SetPoint("TOPRIGHT", -1, -1)
    band:SetHeight(HEADER_H)
    band:SetColorTexture(Theme.bgSub[1], Theme.bgSub[2], Theme.bgSub[3], 0.98)
    local line = frame:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", band, "BOTTOMLEFT")
    line:SetPoint("TOPRIGHT", band, "BOTTOMRIGHT")
    line:SetHeight(2)
    line:SetColorTexture(unpack(Theme.accent))
    frame.icon = frame:CreateTexture(nil, "OVERLAY")
    frame.icon:SetSize(20, 20)
    frame.icon:SetPoint("LEFT", band, "LEFT", 8, 0)
    frame.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("LEFT", frame.icon, "RIGHT", 8, 0)
    frame.title:SetTextColor(unpack(Theme.accent))
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetSize(24, 24)
    close:SetPoint("RIGHT", band, "RIGHT", -2, 0)
    close:SetScript("OnClick", function()
        ns.DB.levelOpen = false
        frame:Hide()
    end)
    local profButton = flatButton(frame, 110, 20, false)
    profButton:SetPoint("RIGHT", close, "LEFT", -4, 0)
    profButton:SetText(T("prof") .. " ▼")
    profButton:SetScript("OnClick", function(self) showProfMenu(self) end)
    frame.profButton = profButton
    local menu = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    ns.UIKit:ApplyBackdrop(menu)
    menu:SetBackdropColor(0.071, 0.094, 0.122, 0.97)
    menu:SetBackdropBorderColor(unpack(Theme.border))
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:EnableMouse(true)
    menu:Hide()
    menu.buttons = {}
    frame.profMenu = menu
    frame:HookScript("OnHide", function() menu:Hide() end)

    -- skill bar: now -> target, training caps marked
    local bar = CreateFrame("StatusBar", nil, frame, "BackdropTemplate")
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -(HEADER_H + 12))
    bar:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
    bar:SetHeight(16)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar:SetStatusBarColor(0.29, 0.55, 0.25, 0.95)
    ns.UIKit:ApplyBackdrop(bar)
    bar:SetBackdropColor(0.047, 0.067, 0.086, 0.96)
    bar:SetBackdropBorderColor(unpack(Theme.border))
    bar.marks = {}
    for i = 1, #Leveling.TIERS do
        local mark = bar:CreateTexture(nil, "OVERLAY")
        mark:SetWidth(1)
        mark:SetColorTexture(1, 1, 1, 0.35)
        bar.marks[i] = mark
    end
    bar.cap = bar:CreateTexture(nil, "OVERLAY")
    bar.cap:SetWidth(2)
    bar.cap:SetColorTexture(1, 0.82, 0, 0.9)
    bar.goal = bar:CreateTexture(nil, "OVERLAY")
    bar.goal:SetWidth(2)
    bar.goal:SetColorTexture(unpack(Theme.accent))
    bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.text:SetPoint("CENTER")
    frame.skillBar = bar

    -- target and trainer recipes
    local y1 = -(HEADER_H + 38)
    local targetLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    targetLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, y1 - 3)
    targetLabel:SetText(T("target"))
    local function stepTarget(delta)
        local by = (IsShiftKeyDown and IsShiftKeyDown()) and 25 or 5
        local from = state.rank or 1
        local t = (state.target or from) + delta * by
        t = max(min(from + 1, Leveling.MAX_SKILL), min(Leveling.MAX_SKILL, t))
        ns.DB.levelTarget = type(ns.DB.levelTarget) == "table" and ns.DB.levelTarget or {}
        ns.DB.levelTarget[state.prof] = t
        state.stepOffset, state.shopOffset = 0, 0
        Panel.Refresh()
    end
    local minus = flatButton(frame, 20, 20, false, function() stepTarget(-1) end)
    minus:SetPoint("LEFT", targetLabel, "RIGHT", 8, 0)
    minus:SetText("-")
    frame.targetValue = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.targetValue:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    frame.targetValue:SetWidth(32)
    local plus = flatButton(frame, 20, 20, false, function() stepTarget(1) end)
    plus:SetPoint("LEFT", frame.targetValue, "RIGHT", 4, 0)
    plus:SetText("+")
    for _, b in ipairs({ minus, plus }) do
        b:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(T("target"), unpack(Theme.accent))
            GameTooltip:AddLine(T("targetTip"), 0.93, 0.96, 0.97, true)
            addTag(GameTooltip)
        end)
        b:HookScript("OnLeave", GameTooltip_Hide)
    end
    local trainer = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    trainer:SetSize(22, 22)
    trainer:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -150, y1)
    local trainerLabel = trainer.Text or trainer.text or trainer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    trainerLabel:ClearAllPoints()
    trainerLabel:SetPoint("LEFT", trainer, "RIGHT", 0, 1)
    trainerLabel:SetFontObject("GameFontHighlightSmall")
    trainerLabel:SetText(T("trainer"))
    trainerLabel:SetWidth(128)
    trainerLabel:SetJustifyH("LEFT")
    trainer:SetScript("OnClick", function(self)
        ns.DB.levelTrainer = self:GetChecked() and true or false
        Panel.Refresh()
    end)
    trainer:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(T("trainer"), unpack(Theme.accent))
        GameTooltip:AddLine(T("trainerTip"), 0.93, 0.96, 0.97, true)
        addTag(GameTooltip)
    end)
    trainer:SetScript("OnLeave", GameTooltip_Hide)
    frame.trainer, frame.trainerLabel = trainer, trainerLabel

    -- prices
    local y2 = y1 - 26
    frame.priceText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.priceText:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, y2 - 4)
    frame.priceText:SetJustifyH("LEFT")
    local scanButton = flatButton(frame, 96, 20, false, function()
        local how = Prices.Scan()
        print(PREFIX .. (how and T("scanStarted") or T("scanClosed")))
        Panel.QueueRefresh()
    end)
    scanButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, y2)
    scanButton:SetText(T("scan"))
    scanButton:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(T("scan"), unpack(Theme.accent))
        GameTooltip:AddLine(T("scanTip"), 0.93, 0.96, 0.97, true)
        addTag(GameTooltip)
    end)
    scanButton:HookScript("OnLeave", GameTooltip_Hide)
    frame.scanButton = scanButton

    -- summary
    frame.summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.summary:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, y2 - 26)
    frame.summary:SetJustifyH("LEFT")

    -- steps and shopping list
    frame.stepsLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.stepsLabel:SetText(T("steps"))
    frame.stepsBox = makeBox(frame)
    frame.stepsBox:SetScript("OnMouseWheel", function(_, delta)
        state.stepOffset = state.stepOffset - delta * 4
        drawSteps()
    end)
    frame.shopLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.shopLabel:SetText(T("shopping"))
    frame.shopBox = makeBox(frame)
    frame.shopBox:SetScript("OnMouseWheel", function(_, delta)
        state.shopOffset = state.shopOffset - delta * 3
        drawShop()
    end)

    -- total and the next recipe
    frame.total = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.total:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 40)
    frame.total:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
    frame.total:SetJustifyH("LEFT")
    local nextButton = flatButton(frame, W - 24, 26, true, function() Panel.Select(currentStep()) end)
    nextButton:SetPoint("BOTTOM", frame, "BOTTOM", 0, 8)
    nextButton:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(T("tab"), unpack(Theme.accent))
        GameTooltip:AddLine(T("nextTip"), 0.93, 0.96, 0.97, true)
        addTag(GameTooltip)
    end)
    nextButton:HookScript("OnLeave", GameTooltip_Hide)
    frame.nextButton = nextButton

    frame:SetScript("OnShow", function() Panel.Refresh() end)
    frame:SetScript("OnHide", function() if ns.UpdateTabChecks then ns.UpdateTabChecks() end end)
    frame:SetScript("OnSizeChanged", function() Panel.Layout() if frame:IsShown() then Panel.Draw() end end)

    local events = {
        "TRADE_SKILL_LIST_UPDATE", "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL", "BAG_UPDATE_DELAYED",
        "GET_ITEM_INFO_RECEIVED", "LEARNED_SPELL_IN_TAB", "NEW_RECIPE_LEARNED",
    }
    for _, event in ipairs(events) do pcall(frame.RegisterEvent, frame, event) end
    frame:SetScript("OnEvent", function() Panel.QueueRefresh() end)

    table.insert(UISpecialFrames, "EzWoWProfessionLevelingFrame")
    if ns.GamePad and ns.GamePad.RegisterWindow then pcall(ns.GamePad.RegisterWindow, frame) end
    Panel.Layout()
    return frame
end

-----------------------------------------------------------------------------
-- Opening
-----------------------------------------------------------------------------
local function isCrafting(id) return ns.Data[id] and not Leveling.GATHERING[id] end

-- the open profession window's profession (when the character has it), else the
-- one last planned, else a learned crafting profession that is not maxed yet
local function pickProfession()
    local host = browser().resolveHostFrame and browser().resolveHostFrame()
    if host and host:IsShown() and browser().resolveCurrentTradeSkillLine then
        local line = browser().resolveCurrentTradeSkillLine()
        if line and isCrafting(line) and Leveling.SkillOf(line) then return line end
    end
    if state.prof and ns.Data[state.prof] then return state.prof end
    local fallback
    for _, p in ipairs(ns.PROFESSIONS or {}) do
        if isCrafting(p.id) then
            local rank = Leveling.SkillOf(p.id)
            if rank and rank < Leveling.MAX_SKILL then return p.id end
            if rank and not fallback then fallback = p.id end
        end
    end
    return fallback or 197
end

function ns.ToggleLeveling(skillLine)
    Panel.Build()
    if frame:IsShown() and not skillLine then
        ns.DB.levelOpen = false
        frame:Hide()
        return
    end
    state.prof = skillLine or pickProfession()
    state.stepOffset, state.shopOffset = 0, 0
    ns.DB.levelUsed, ns.DB.levelOpen = true, true
    Panel.Dock()
    frame:Show()
    Panel.Refresh()
end

-- profession window opened or switched: follow it (and come back if it was left open)
function Panel.OnHostShown()
    if not ns.DB or not ns.DB.levelOpen then return end
    C_Timer.After(0.35, function()
        local host = browser().resolveHostFrame and browser().resolveHostFrame()
        if not (host and host:IsShown()) then return end
        Panel.Build()
        local line = browser().resolveCurrentTradeSkillLine and browser().resolveCurrentTradeSkillLine()
        if line and isCrafting(line) and Leveling.SkillOf(line) then state.prof = line end
        if not state.prof then state.prof = pickProfession() end
        state.stepOffset, state.shopOffset = 0, 0
        Panel.Dock()
        frame:Show()
        Panel.Refresh()
    end)
end

function Panel.OnHostHidden()
    if frame and frame:IsShown() and frame.docked then frame:Hide() end
end

-- ============================================================================
-- AscensionFR - Noyau
-- Moteur de substitution, accès aux bases de données, utilitaires partagés.
-- ============================================================================
AscensionFR = AscensionFR or {}
local AFR = AscensionFR

-- Les bases de données sont remplies par les fichiers DB\*.lua (générés).
-- ----------------------------------------------------------------------------
-- Chargement à la demande (#33, 21/07/2026). Une grande table n'est d'abord
-- que des MORCEAUX de source Lua (des chaînes, peu coûteuses) ; le premier
-- accès à un id compile le seau de cet id (512 entrées), le verse dans la
-- table, puis jette le morceau. 70 000 objets ne pèsent en mémoire que ce
-- que le joueur a réellement survolé. LIMITE : une table paresseuse ne se
-- parcourt PAS avec pairs() — réservée aux bases à accès par identifiant.
-- ----------------------------------------------------------------------------
function AFR.Paresseux(morceaux, taille_seau)
    local paresseuse = {}
    setmetatable(paresseuse, { __index = function(self, id)
        if type(id) ~= "number" then return nil end
        local seau = math.floor(id / taille_seau)
        local morceau = morceaux[seau]
        if not morceau then return nil end
        morceaux[seau] = nil        -- un seau ne se compile qu'une fois
        local usine = loadstring("return {" .. morceau .. "}")
        if not usine then return nil end
        local ok, entrees = pcall(usine)
        if not ok or type(entrees) ~= "table" then return nil end
        for cle, valeur in pairs(entrees) do
            rawset(self, cle, valeur)
        end
        return rawget(self, id)
    end })
    return paresseuse
end

-- ----------------------------------------------------------------------------
-- Chargement à la demande par TEXTE (2.0.1, 21/07/2026 — les mini-blocages
-- de Ruxar et Dan : plus la mémoire vive du jeu est grosse, plus son
-- « ménage » périodique se sent). Une table interrogée par texte exact ne
-- peut pas utiliser AFR.Paresseux (clés numériques). Ici, chaque seau
-- (premier octet de la clé) porte d'abord une CHAÎNE DE PRÉSENCE : on y
-- cherche « \1texte\1 » (recherche C, aucun objet créé) — et 99 % des
-- textes de l'interface n'y sont pas, réponse immédiate sans rien
-- compiler. Seul un texte PRÉSENT compile son seau, une fois.
-- LIMITE : pas de pairs() — accès par clé exacte uniquement.
-- ----------------------------------------------------------------------------
function AFR.ParesseuxTexte(cles, morceaux)
    local paresseuse = {}
    setmetatable(paresseuse, { __index = function(self, cle)
        if type(cle) ~= "string" or cle == "" then return nil end
        local octet = string.byte(cle)
        local presence = cles[octet]
        if not presence then return nil end
        if not string.find(presence, "\\1" .. cle .. "\\1", 1, true) then
            return nil
        end
        local morceau = morceaux[octet]
        if not morceau then return rawget(self, cle) end
        morceaux[octet] = nil       -- un seau ne se compile qu'une fois
        local usine = loadstring("return {" .. morceau .. "}")
        if not usine then return nil end
        local ok, entrees = pcall(usine)
        if not ok or type(entrees) ~= "table" then return nil end
        for k, v in pairs(entrees) do
            rawset(self, k, v)
        end
        return rawget(self, cle)
    end })
    return paresseuse
end

AFR.DB = {
    Quetes      = {},   -- [idQuete]    = {TE, T, O, D, F, A, P, R, OT}
    Objets      = {},   -- [idObjet]    = {N, D} (rendue paresseuse par
                        -- outils\\optimiser_memoire.py après génération)
    SortsNoms   = {},   -- [nom EN]     = nom FR (pont grimoire/barres)
    Creatures   = {},   -- [idCreature] = {NE, N, SE, S}
    ObjetsMonde = {},   -- [idObjet]    = {NE, N}
    TextesPNJ   = {},   -- [texteEN]    = texteFR   (dialogues de PNJ)
    Gossip      = {},   -- [texteEN]    = texteFR   (options de dialogue)
    Pages       = {},   -- [texteEN]    = texteFR   (pages de livres)
    Sorts       = {},   -- [idSort]     = {N, D}
    Divers      = {},   -- [texteEN]    = texteFR   (fourre-tout appris)
    Repliques   = {},   -- [texteEN]    = texteFR   (paroles des PNJ)
    Libelles    = {},   -- [texteEN]    = texteFR   (sous-classes, métiers : DBC)
    Epreuves    = {},   -- [texteEN]    = texteFR   (fenêtre « Trials »,
                        --                           lue dans Challenge.dbc)
    Zones       = {},   -- [texteEN]    = texteFR   (noms de zones : frFR
                        --                           officiel, traduire_zones)
    ObjetsNoms  = {},   -- [nomEN]      = nomFR     (pont des noms d'objets :
                        --                           TDB × customs, objectifs)
    QuetesObjectifs = {}, -- [objectifEN] = objectifFR (phrases du suivi :
                        --                           TDB LogDescription)
    HautsFaits  = {},   -- [texteEN]    = texteFR   (Achievement.dbc :
                        --                           officiel frFR + machine)
    AddonsTiers = {},   -- [appAceLocale] = {texteEN = texteFR}
                        --   Addons des autres (DragonUI…). On injecte dans
                        --   LEUR table AceLocale : aucun de leurs fichiers
                        --   n'est modifié, leurs mises à jour n'effacent rien.
    UI          = {},   -- [GLOBALE]    = texteFR   (GlobalStrings frFR)
    ListeNoire  = {},   -- [GLOBALE]    = true      (à ne jamais traduire :
                        --                           contaminerait le jeu)
    Reglages    = {},   -- [GLOBALE]    = true      (réglages du panneau
                        --                           d'options : les traduire
                        --                           bloque les sorts en combat)
    LuesClient  = {},   -- [GLOBALE]    = true      (toute globale que le code
                        --                           du client LIT : 2 208 sur
                        --                           13 552. Écrire l'une
                        --                           d'elles souille le jeu.)
}

-- ----------------------------------------------------------------------------
-- Substitution des variables des textes officiels ($n, $b, $c, $r, $g...)
--
-- Races et classes viennent de DB.Libelles, extraite des DBC du client
-- (outils/extraire_libelles.py) : le frFR officiel par identifiant pour les
-- races et classes de Blizzard, une liste écrite à la main pour les 22
-- classes maison d'Ascension.
--
-- Il y avait ici deux tables écrites de mémoire. Elles inventaient des
-- classes qui n'existent pas (« Son of Arugal », « Bard », « Monk ») et
-- manquaient les vraies (« Templar », « Felsworn », « Runemaster ») : le
-- joueur templier lisait « Templar » dans ses textes de quête. Recenser,
-- jamais deviner — la règle vaut aussi pour ce qu'on croit savoir du jeu.
-- ----------------------------------------------------------------------------
local function ValeurJoueur()
    local nom = UnitName("player") or "Aventurier"
    local classeEN = UnitClass("player")
    local raceEN = UnitRace("player")
    -- Un nom identique en français (« Mage », « Paladin », « Orc ») n'est pas
    -- dans la base : l'anglais est alors la bonne réponse.
    local classe = (classeEN and AFR.DB.Libelles[classeEN])
        or classeEN or "aventurier"
    local race = (raceEN and AFR.DB.Libelles[raceEN]) or raceEN or ""
    local sexe = UnitSex("player") -- 2 = masculin, 3 = féminin
    return nom, classe, race, sexe
end

function AFR.Substituer(texte)
    if not texte or texte == "" then return texte end
    local nom, classe, race, sexe = ValeurJoueur()
    -- $b = saut de ligne
    texte = string.gsub(texte, "%$[Bb]", "\\n")
    -- $n = nom du joueur ; $c = classe ; $r = race (remplacement par fonction
    -- pour neutraliser les caractères spéciaux de gsub comme %)
    texte = string.gsub(texte, "%$[Nn]", function() return nom end)
    texte = string.gsub(texte, "%$[Cc]", function() return classe end)
    texte = string.gsub(texte, "%$[Rr]", function() return race end)
    -- $g masculin:féminin; (accord de genre, fréquent dans le frFR officiel)
    texte = string.gsub(texte, "%$[Gg]%s*([^:;]-):([^;]-);", function(m, f)
        if sexe == 3 then return f else return m end
    end)
    return texte
end

-- ----------------------------------------------------------------------------
-- Recherche par texte : les textes reçus du serveur ont déjà le nom du joueur
-- substitué ; on essaie aussi la version « modèle » avec $n.
-- ----------------------------------------------------------------------------

-- Cherche une clé et ses variantes « nom du joueur -> $n ».
local function ChercherVariantes(db, t, nom)
    local fr = db[t]
    if fr then return fr end
    if nom and nom ~= "" then
        local modele = string.gsub(t, nom, "$n")
        if modele ~= t then
            fr = db[modele]
            if fr then return fr end
            modele = string.gsub(t, nom, "$N")
            fr = db[modele]
            if fr then return fr end
        end
    end
    return nil
end

function AFR.ChercherParTexte(db, texte)
    if not texte or texte == "" then return nil end
    -- Fins de ligne normalisées (\n, pas \r\n), comme les clés des bases.
    local brut = string.gsub(texte, "\\r\\n", "\\n")
    local nom = UnitName("player")
    -- On essaie D'ABORD le texte tel quel, PUIS élagué. Les paroles de PNJ
    -- gardent parfois un espace de tête (format du serveur, 21 sur 69 477) :
    -- élaguer d'emblée ne les trouvait jamais. Le message reçu porte le même
    -- espace que la clé, donc la version brute matche directement.
    local fr = ChercherVariantes(db, brut, nom)
    if fr then return fr end
    local elague = strtrim(brut)
    if elague ~= brut then
        return ChercherVariantes(db, elague, nom)
    end
    return nil
end

-- Index inversés construits à la demande (titre EN -> id, nom EN -> id...)
local indexTitresQuetes, indexNomsCreatures, indexNomsObjetsMonde

function AFR.QueteParTitreEN(titre)
    if not indexTitresQuetes then
        indexTitresQuetes = {}
        for id, q in pairs(AFR.DB.Quetes) do
            if q.TE then indexTitresQuetes[q.TE] = id end
        end
    end
    local id = indexTitresQuetes[titre]
    return id and AFR.DB.Quetes[id], id
end

function AFR.CreatureParNomEN(nom)
    if not indexNomsCreatures then
        indexNomsCreatures = {}
        for id, c in pairs(AFR.DB.Creatures) do
            if c.NE then indexNomsCreatures[c.NE] = id end
        end
    end
    local id = indexNomsCreatures[nom]
    return id and AFR.DB.Creatures[id], id
end

function AFR.ObjetMondeParNomEN(nom)
    if not indexNomsObjetsMonde then
        indexNomsObjetsMonde = {}
        for id, o in pairs(AFR.DB.ObjetsMonde) do
            if o.NE then indexNomsObjetsMonde[o.NE] = id end
        end
    end
    local id = indexNomsObjetsMonde[nom]
    return id and AFR.DB.ObjetsMonde[id], id
end

-- ----------------------------------------------------------------------------
-- PRÉCHAUFFAGE (2.0.2). Chaque index inversé ci-dessus se construit à sa
-- PREMIÈRE demande : un pic de travail qui tombait en pleine partie — un
-- mini-blocage par index, éparpillés dans les premières minutes (vécu le
-- soir de la 2.0). On les construit pendant l'ÉCRAN DE CHARGEMENT, où
-- personne ne sent rien. Les modules peuvent inscrire leurs propres index
-- dans AFR.Prechauffages (Normalisee des Épreuves, plaques...).
-- ----------------------------------------------------------------------------
AFR.Prechauffages = {}
local chauffe = CreateFrame("Frame")
chauffe:RegisterEvent("PLAYER_ENTERING_WORLD")
chauffe:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")   -- une fois par session
    pcall(AFR.QueteParTitreEN, "préchauffage")
    pcall(AFR.CreatureParNomEN, "préchauffage")
    pcall(AFR.ObjetMondeParNomEN, "préchauffage")
    for _, f in ipairs(AFR.Prechauffages) do pcall(f) end
end)

-- ----------------------------------------------------------------------------
-- Parcours générique d'une fenêtre
--
-- Ascension réécrit ses fenêtres (journal de quêtes, métiers, grimoire) : leurs
-- noms de cadres sont inconnus et changent. On ne nomme donc aucun cadre : on
-- construit une table « texte anglais -> texte français » à partir des données
-- du jeu, puis on remplace le texte de chaque zone reconnue.
--
-- RÈGLE DE SÛRETÉ : ne jamais écrire dans un cadre protégé — cela contamine le
-- chemin d'exécution et le jeu refuse ensuite les actions du joueur
-- (« tainted the call of the secure function 'UseAction()' »). IsProtected()
-- nous le dit sans avoir à deviner.
-- ----------------------------------------------------------------------------
function AFR.EstProtege(cadre)
    if not cadre or type(cadre.IsProtected) ~= "function" then return false end
    local ok, protege = pcall(cadre.IsProtected, cadre)
    return ok and protege
end

function AFR.Parcourir(cadre, correspondances, profondeur)
    profondeur = profondeur or 0
    if not cadre or profondeur > 6 then return end
    if AFR.EstProtege(cadre) then return end
    if cadre.GetRegions then
        local regions = { cadre:GetRegions() }
        for _, region in ipairs(regions) do
            if region and region.GetObjectType
                and region:GetObjectType() == "FontString" then
                local texte = region:GetText()
                if texte then
                    local fr = correspondances[texte]
                    if not fr then
                        -- « Nom [3] » : la fenêtre des métiers colle le
                        -- compteur de fabrications possibles au nom de la
                        -- recette, dans la même zone de texte.
                        local corps, suffixe =
                            string.match(texte, "^(.-)(%s*%[%d+%])$")
                        if corps and correspondances[corps] then
                            fr = correspondances[corps] .. suffixe
                        end
                    end
                    if fr then region:SetText(fr) end
                end
            end
        end
    end
    if cadre.GetChildren then
        local enfants = { cadre:GetChildren() }
        for _, enfant in ipairs(enfants) do
            AFR.Parcourir(enfant, correspondances, profondeur + 1)
        end
    end
end

-- ----------------------------------------------------------------------------
-- Extraction d'identifiants
-- ----------------------------------------------------------------------------
function AFR.IdDepuisLienObjet(lien)
    if not lien then return nil end
    local id = string.match(lien, "item:(%d+)")
    return id and tonumber(id)
end

function AFR.IdDepuisLienQuete(lien)
    if not lien then return nil end
    local id = string.match(lien, "quest:(%d+)")
    return id and tonumber(id)
end

-- GUID 3.3.5 : 0xF130EEEEEESSSSSS -> EEEEEE = id de créature (hexadécimal)
function AFR.IdCreatureDepuisGUID(guid)
    if not guid or type(guid) ~= "string" then return nil end
    local typeHex = string.sub(guid, 3, 6)
    if typeHex == "F130" or typeHex == "F530" or typeHex == "F150" then
        local ok, id = pcall(tonumber, string.sub(guid, 7, 12), 16)
        if ok and id and id > 0 then return id end
    end
    return nil
end

-- ----------------------------------------------------------------------------
-- Traduction d'une ligne d'objectif (« Mangy Nightsaber slain: 3/5 »)
-- ----------------------------------------------------------------------------
local SuffixesObjectifs = {
    [" slain"] = " tué(s)",
    [" killed"] = " tué(s)",
    [" destroyed"] = " détruit(s)",
    [" freed"] = " libéré(s)",
    [" rescued"] = " secouru(s)",
    [" escorted"] = " escorté(s)",
    [" completed"] = " accompli(s)",
    [" discovered"] = " découvert(s)",
}

function AFR.TraduireObjectif(texte)
    if not texte then return nil end
    -- Correspondance exacte apprise
    local fr = AFR.ChercherParTexte(AFR.DB.Divers, texte)
    if fr then return fr end
    -- Motif générique « Nom truc: x/y »
    local corps, x, y = string.match(texte, "^(.-)%s*:%s*(%d+)%s*/%s*(%d+)%s*$")
    if not corps then return nil end
    local traduit = false
    -- Suffixe d'action connu ?
    for en, frs in pairs(SuffixesObjectifs) do
        local avant = string.sub(corps, 1, -(#en) - 1)
        if string.sub(corps, -(#en)) == en and avant ~= "" then
            local c = AFR.CreatureParNomEN(avant)
            local nomFR = c and c.N
            if not nomFR then
                local o = AFR.ObjetMondeParNomEN(avant)
                nomFR = o and o.N
            end
            if not nomFR then
                nomFR = AFR.DB.Divers[avant]
            end
            corps = (nomFR or avant) .. frs
            traduit = true
            break
        end
    end
    if not traduit then
        -- Objet à ramasser : le corps est un nom d'objet ou de créature
        local c = AFR.CreatureParNomEN(corps)
        local nomFR = c and c.N
        if not nomFR then
            local o = AFR.ObjetMondeParNomEN(corps)
            nomFR = o and o.N
        end
        if not nomFR then nomFR = AFR.DB.Divers[corps] end
        if nomFR then
            corps = nomFR
            traduit = true
        end
    end
    if traduit then
        return corps .. " : " .. x .. "/" .. y
    end
    return nil
end

-- ----------------------------------------------------------------------------
-- Options et journalisation
-- ----------------------------------------------------------------------------
function AFR.Actif()
    return not (AscensionFRSaved and AscensionFRSaved.Options
        and AscensionFRSaved.Options.desactive)
end

-- Journal en mémoire : tout ce que l'addon fait ou écarte, lisible dans le
-- panneau (sous-catégorie « Journal ») plutôt que dans le chat. Borné : les
-- plus vieilles lignes tombent.
AFR.Journal = {}
local JOURNAL_MAX = 250

-- Les relevés volumineux et répétitifs (une ligne par chaîne écartée...)
-- noieraient le journal : ils sont rangés à part, résumés en une ligne dans
-- le journal et joints en entier au partage.
AFR.Details = {}
local DETAILS_MAX = 400

function AFR.Detailler(rubrique, ligne)
    local d = AFR.Details[rubrique]
    if not d then
        d = {}
        AFR.Details[rubrique] = d
    end
    if #d < DETAILS_MAX then d[#d + 1] = tostring(ligne) end
end

function AFR.Journaliser(...)
    local morceaux = {}
    for i = 1, select("#", ...) do
        morceaux[i] = tostring(select(i, ...))
    end
    local heure = type(date) == "function" and date("%H:%M:%S") or ""
    local j = AFR.Journal
    j[#j + 1] = heure .. "  " .. table.concat(morceaux, " ")
    if #j > JOURNAL_MAX then table.remove(j, 1) end
    -- Le panneau, s'il est ouvert, s'abonne pour afficher en direct.
    if AFR.JournalEcoute then AFR.JournalEcoute(j[#j]) end
end

function AFR.Debug(...)
    AFR.Journaliser(...)
    -- La copie dans le chat reste possible, mais c'est une option.
    if AscensionFRSaved and AscensionFRSaved.Options
        and AscensionFRSaved.Options.debug then
        print("|cff0099ffAFR|r:", ...)
    end
end

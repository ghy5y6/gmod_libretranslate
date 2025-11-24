-- Shared ConVar: replicated and archived so it syncs to server and saves to config
local TranslateURLConVar = CreateConVar("libretranslate_url", "https://eff5a18966b3.ngrok-free.app/translate", FCVAR_ARCHIVE + FCVAR_REPLICATED, "URL for the LibreTranslate API endpoint")
local TargetLangConVar = CreateConVar("libretranslate_target", "ru", FCVAR_ARCHIVE + FCVAR_REPLICATED, "Target language code (default: ru for Russian)")

-- All supported languages from LibreTranslate API
local LANGUAGES = {
    ["en"] = "English",
    ["sq"] = "Albanian",
    ["ar"] = "Arabic",
    ["az"] = "Azerbaijani",
    ["eu"] = "Basque",
    ["bn"] = "Bengali",
    ["bg"] = "Bulgarian",
    ["ca"] = "Catalan",
    ["zh-Hans"] = "Chinese (Simplified)",
    ["zh-Hant"] = "Chinese (Traditional)",
    ["cs"] = "Czech",
    ["da"] = "Danish",
    ["nl"] = "Dutch",
    ["eo"] = "Esperanto",
    ["et"] = "Estonian",
    ["fi"] = "Finnish",
    ["fr"] = "French",
    ["gl"] = "Galician",
    ["de"] = "German",
    ["el"] = "Greek",
    ["he"] = "Hebrew",
    ["hi"] = "Hindi",
    ["hu"] = "Hungarian",
    ["id"] = "Indonesian",
    ["ga"] = "Irish",
    ["it"] = "Italian",
    ["ja"] = "Japanese",
    ["ko"] = "Korean",
    ["ky"] = "Kyrgyz",
    ["lv"] = "Latvian",
    ["lt"] = "Lithuanian",
    ["ms"] = "Malay",
    ["nb"] = "Norwegian",
    ["fa"] = "Persian",
    ["pl"] = "Polish",
    ["pt"] = "Portuguese",
    ["pt-BR"] = "Portuguese (Brazil)",
    ["ro"] = "Romanian",
    ["ru"] = "Russian",
    ["sr"] = "Serbian",
    ["sk"] = "Slovak",
    ["sl"] = "Slovenian",
    ["es"] = "Spanish",
    ["sv"] = "Swedish",
    ["tl"] = "Tagalog",
    ["th"] = "Thai",
    ["tr"] = "Turkish",
    ["uk"] = "Ukrainian",
    ["ur"] = "Urdu"
}

if SERVER then
    util.AddNetworkString("LibreTranslate_SendClipboard")
    util.AddNetworkString("LibreTranslate_SendLanguages")
    util.AddNetworkString("LibreTranslate_NotifyURL")

    -- Function to check if URL is a ngrok URL
    local function IsNgrokURL(url)
        return url and string.find(url, "ngrok%-free%.app") ~= nil
    end

    -- Notify players about ngrok URL when they join
    hook.Add("PlayerInitialSpawn", "LibreTranslate_NotifyPlayer", function(ply)
        local url = GetConVarString("libretranslate_url")
        if IsNgrokURL(url) then
            timer.Simple(5, function()
                if IsValid(ply) then
                    net.Start("LibreTranslate_NotifyURL")
                    net.Send(ply)
                end
            end)
        end
    end)

    local function PerformTranslation(ply, text, targetLang)
        if not IsValid(ply) then return end
        if text == "" then
            ply:ChatPrint("Usage: /tr <text> or /tr <lang> <text>")
            return
        end

        -- Get the current URL from the ConVar (server-side)
        local TRANSLATE_URL = GetConVarString("libretranslate_url")
        if not TRANSLATE_URL or TRANSLATE_URL:Trim() == "" then
            ply:ChatPrint("Translation URL is not set! Use 'libretranslate_menu' to configure it.")
            return
        end

        -- Use provided target language or get from ConVar
        targetLang = targetLang or GetConVarString("libretranslate_target") or "ru"

        local postData = {
            q = text,
            source = "auto",
            target = targetLang,
            format = "text",
            alternatives = 1,
            api_key = ""
        }

        local jsonBody = util.TableToJSON(postData)

        HTTP({
            url = TRANSLATE_URL,
            method = "POST",
            headers = {
                ["Content-Type"] = "application/json; charset=utf-8",
                ["Accept"] = "application/json"
            },
            body = jsonBody,
            success = function(code, body, headers)
                if code ~= 200 then
                    if code == 404 then
                        ply:ChatPrint("Translation endpoint not found (HTTP 404)")
                        ply:ChatPrint("If using ngrok, make sure it's running or update the URL with 'libretranslate_menu'")
                    else
                        ply:ChatPrint("Translation server error (HTTP " .. code .. ")")
                    end
                    return
                end

                local result = util.JSONToTable(body)
                if not result or not result.translatedText then
                    ply:ChatPrint("Invalid translation response")
                    return
                end

                local translated = result.translatedText

                net.Start("LibreTranslate_SendClipboard")
                net.WriteString(translated)
                net.Send(ply)
            end,
            failed = function(err)
                ply:ChatPrint("Connection failed: " .. tostring(err or "unknown error"))
                ply:ChatPrint("If using ngrok, make sure it's running or update the URL with 'libretranslate_menu'")
            end
        })
    end

    hook.Add("PlayerSay", "LibreTranslate_ChatCommand", function(ply, text, team)
        if string.sub(text, 1, 3) == "/tr" then
            local args = string.Trim(string.sub(text, 4))
            if args == "" then
                ply:ChatPrint("Usage: /tr <text> or /tr <lang> <text>")
                return ""
            end

            -- Check if first argument is a language code
            local langCode = string.match(args, "^(%w%w%-%?%w?%w?) ")
            if langCode and LANGUAGES[langCode] then
                local textToTranslate = string.Trim(string.sub(args, #langCode + 2))
                if textToTranslate == "" then
                    ply:ChatPrint("Usage: /tr <lang> <text>")
                    return ""
                end
                PerformTranslation(ply, textToTranslate, langCode)
            else
                PerformTranslation(ply, args)
            end
            return ""
        end
    end)

    -- Command to change target language
    concommand.Add("libretranslate_setlang", function(ply, cmd, args)
        if not IsValid(ply) then return end
        
        local langCode = args[1]
        if not langCode or not LANGUAGES[langCode] then
            ply:ChatPrint("Invalid language code. Use 'libretranslate_menu' to see available languages.")
            return
        end
        
        ply:ConCommand("libretranslate_target " .. langCode)
        ply:ChatPrint("Translation language set to " .. LANGUAGES[langCode] .. " (" .. langCode .. ")")
    end)

    -- Send available languages to client when they request them
    net.Receive("LibreTranslate_SendLanguages", function(len, ply)
        net.Start("LibreTranslate_SendLanguages")
        net.WriteTable(LANGUAGES)
        net.Send(ply)
    end)
end

if CLIENT then
    net.Receive("LibreTranslate_SendClipboard", function()
        local translated = net.ReadString()
        SetClipboardText(translated)
        chat.AddText(Color(0, 200, 0), "Translated text copied to clipboard!")
    end)

    net.Receive("LibreTranslate_SendLanguages", function()
        LANGUAGES = net.ReadTable()
    end)

    -- Notification about ngrok URL
    net.Receive("LibreTranslate_NotifyURL", function()
        chat.AddText(Color(255, 200, 0), "[LibreTranslate] You're using a local ngrok URL for translation.")
        chat.AddText(Color(255, 200, 0), "[LibreTranslate] If translation fails, make sure ngrok is running or update the URL.")
    end)

    -- Command to open the settings menu
    concommand.Add("libretranslate_menu", function()
        -- Request languages from server if we don't have them
        if not LANGUAGES then
            net.Start("LibreTranslate_SendLanguages")
            net.SendToServer()
            timer.Simple(0.5, function() 
                if LANGUAGES then
                    CreateSettingsMenu()
                end
            end)
        else
            CreateSettingsMenu()
        end
    end)

    function CreateSettingsMenu()
        local frame = vgui.Create("DFrame")
        frame:SetSize(500, 280)
        frame:Center()
        frame:SetTitle("LibreTranslate Settings")
        frame:SetVisible(true)
        frame:SetDraggable(true)
        frame:ShowCloseButton(true)
        frame:MakePopup()
        frame.Paint = function(self, w, h)
            draw.RoundedBox(4, 0, 0, w, h, Color(30, 30, 35, 240))
        end

        local urlEntry = vgui.Create("DTextEntry", frame)
        urlEntry:SetPos(10, 35)
        urlEntry:SetSize(480, 24)
        
        -- Get the current URL and remove /translate for display
        local currentURL = GetConVarString("libretranslate_url")
        local displayURL = string.gsub(currentURL, "/translate$", "")
        urlEntry:SetText(displayURL)

        local langLabel = vgui.Create("DLabel", frame)
        langLabel:SetText("Target Language:")
        langLabel:SetPos(10, 70)
        langLabel:SetColor(Color(220, 220, 220))
        langLabel:SizeToContents()

        local langComboBox = vgui.Create("DComboBox", frame)
        langComboBox:SetPos(10, 95)
        langComboBox:SetSize(480, 24)
        
        -- Variable to store the selected language
        local selectedLang = GetConVarString("libretranslate_target") or "ru"
        
        -- Add languages to the combo box
        if LANGUAGES then
            local firstOption = nil
            for code, name in pairs(LANGUAGES) do
                local choiceText = name .. " (" .. code .. ")"
                langComboBox:AddChoice(choiceText, code)
                
                -- Store the first option to select it later if needed
                if not firstOption then
                    firstOption = {text = choiceText, code = code}
                end
                
                -- Select the current language
                if code == selectedLang then
                    langComboBox:SetValue(choiceText)
                end
            end
            
            -- If current language wasn't found in the list, select the first option
            if not LANGUAGES[selectedLang] and firstOption then
                langComboBox:SetValue(firstOption.text)
                selectedLang = firstOption.code
            end
        end
        
        -- Update selectedLang when the user selects a different option
        langComboBox.OnSelect = function(panel, index, value, data)
            selectedLang = data
        end

        local applyBtn = vgui.Create("DButton", frame)
        applyBtn:SetPos(10, 135)
        applyBtn:SetSize(100, 30)
        applyBtn:SetText("Apply")
        applyBtn.DoClick = function()
            local newURL = urlEntry:GetValue():Trim()
            if newURL == "" then
                chat.AddText(Color(255, 50, 50), "URL cannot be empty!")
                return
            end
            
            -- Add /translate if it's not already there
            if not string.find(newURL, "/translate$") then
                newURL = newURL .. "/translate"
            end
            
            -- Use the selectedLang variable instead of GetSelectedData()
            RunConsoleCommand("libretranslate_url", newURL)
            RunConsoleCommand("libretranslate_target", selectedLang)
            chat.AddText(Color(0, 200, 0), "Settings updated!")
            frame:Close()
        end

        local cancelBtn = vgui.Create("DButton", frame)
        cancelBtn:SetPos(120, 135)
        cancelBtn:SetSize(100, 30)
        cancelBtn:SetText("Cancel")
        cancelBtn.DoClick = function()
            frame:Close()
        end

        local helpLabel = vgui.Create("DLabel", frame)
        helpLabel:SetText("Usage: /tr <text> or /tr <lang> <text>")
        helpLabel:SetPos(10, 170)
        helpLabel:SetColor(Color(180, 180, 180))
        helpLabel:SizeToContents()

        local langCountLabel = vgui.Create("DLabel", frame)
        langCountLabel:SetText("Supported languages: " .. table.Count(LANGUAGES))
        langCountLabel:SetPos(10, 190)
        langCountLabel:SetColor(Color(180, 180, 180))
        langCountLabel:SizeToContents()
        
        -- Add ngrok warning label
        local url = GetConVarString("libretranslate_url")
        if string.find(url, "ngrok%-free%.app") then
            local ngrokLabel = vgui.Create("DLabel", frame)
            ngrokLabel:SetText("Using local ngrok URL - make sure ngrok is running")
            ngrokLabel:SetPos(10, 210)
            ngrokLabel:SetColor(Color(255, 200, 0))
            ngrokLabel:SizeToContents()
            
            local ngrokLabel2 = vgui.Create("DLabel", frame)
            ngrokLabel2:SetText("URL is displayed without /translate but it's added automatically")
            ngrokLabel2:SetPos(10, 225)
            ngrokLabel2:SetColor(Color(180, 180, 180))
            ngrokLabel2:SizeToContents()
        end
    end

    -- Command to quickly change language without menu
    concommand.Add("libretranslate_lang", function()
        if not LANGUAGES then
            net.Start("LibreTranslate_SendLanguages")
            net.SendToServer()
            timer.Simple(0.5, function() 
                if LANGUAGES then
                    CreateLangMenu()
                end
            end)
        else
            CreateLangMenu()
        end
    end)

    function CreateLangMenu()
        local frame = vgui.Create("DFrame")
        frame:SetSize(300, 500)
        frame:Center()
        frame:SetTitle("Select Translation Language")
        frame:SetVisible(true)
        frame:SetDraggable(true)
        frame:ShowCloseButton(true)
        frame:MakePopup()
        frame.Paint = function(self, w, h)
            draw.RoundedBox(4, 0, 0, w, h, Color(30, 30, 35, 240))
        end

        local scroll = vgui.Create("DScrollPanel", frame)
        scroll:SetPos(10, 30)
        scroll:SetSize(280, 460)

        local currentLang = GetConVarString("libretranslate_target") or "ru"
        
        for code, name in pairs(LANGUAGES) do
            local btn = vgui.Create("DButton", scroll)
            btn:SetPos(0, (btn:GetTall() + 2) * (table.Count(scroll:GetChildren()) - 1))
            btn:SetSize(280, 25)
            btn:SetText(name .. " (" .. code .. ")")
            
            if code == currentLang then
                btn:SetTextColor(Color(0, 200, 0))
            end
            
            btn.DoClick = function()
                RunConsoleCommand("libretranslate_target", code)
                chat.AddText(Color(0, 200, 0), "Translation language set to " .. name .. " (" .. code .. ")")
                frame:Close()
            end
        end
    end
end
-- First function inserts a linebreak where it seems logical - after periods, commas, before "and," etc. If the line has one, it removes it.
--   This will not always produce the desired result, but mostly it works fairly well.
--   There's a limit for how unevenly a line can be split, so if it's over the ratio, it nukes the \N and goes to the next step.
--   If the stuff above didn't work out, a linebreak is inserted in the middle of the line if restrictions in settings allow it.
--   If it doesn't pass set restrictions, it opens a small GUI. Click where you want the break, hit enter, click OK.
--   The "All spaces" option is useful for typesetters when they want each word on a new line.
-- Second function puts a linebreak after the first word. Every new run of the function puts the linebreak one word further.
--   When it reaches the last word, it removes the break.
-- Third function shifts linebreaks back and is disabled by default.
-- You can bind each function to a different hotkey and combine them as needed.

script_name="Line Breaker"
script_description="insert/shift linebreaks"
script_author="unanimated"
script_version="2.1"

--	SETTINGS	--	-- options are either numbers or true/false							[default value]

min_characters=0		-- minimum characters needed to insert a linebreak (ie no breaks in lines under X characters)	[42]
min_words=3			-- minimum words needed to insert a linebreak							[3]
put_break_in_the_middle=true	-- put a linebreak in the middle with the insert function if all else fails			[true]
middle_min_characters=40	-- minimum of characters needed to insert a linebreak in the middle				[45]
force_breaks_in_middle=false	-- force breaks in the middle of the line rather than after commas etc. (not recommended because stupid)
enable_shift_backwards=true	-- enables shifting backwards (adds a new item to the automation menu)				[false]
disable_dialog=false		-- if no break is placed with the insert function, a dialog lets you choose it manually.	[false]
allow_break_between_two=true	-- allow a break if there are only 2 words. good for TS, not much for editing (overrides min_ settings)	[false]
do_balance_checks=true		-- enable checking the ratio between top and bottom line (only for lines with over 4 words)	[true]
max_ratio=2.2			-- maximum ratio between top and bottom line allowed (if previous setting enabled)		[2.2]
do_not_break_1liners=false	-- won't break lines that don't break naturally. disables manual breaking and break between 2.	[false]

--	--	--	--

re=require'aegisub.re'

function esc(str)
str=str:gsub("%%","%%%%")
str=str:gsub("%(","%%%(")
str=str:gsub("%)","%%%)")
str=str:gsub("%[","%%%[")
str=str:gsub("%]","%%%]")
str=str:gsub("%.","%%%.")
str=str:gsub("%*","%%%*")
str=str:gsub("%-","%%%-")
str=str:gsub("%+","%%%+")
str=str:gsub("%?","%%%?")
return str
end

function nnn(subs, sel)
  for i=1, #subs do
    if subs[i].class=="style" then
      local st=subs[i]
      if stylename==st.name then styleref=st end
      if st.name=="Default" then defaref=st defleft=st.margin_l defright=st.margin_r end
    end
    if subs[i].class=="info" then
	local k=subs[i].key
	local v=subs[i].value
	if k=="PlayResX" then resx=v end
	if k=="PlayResY" then resy=v end
    end
    if subs[i].class=="dialogue" then break end
  end

  for x, i in ipairs(sel) do
    aegisub.progress.title(string.format("Processing line: %d/%d",x,#sel))
    line=subs[i]
    text=line.text
	
    if line.style=="Default" then styleref=defaref else styleref=stylechk(subs,line.style) end

	-- remove linebreak if there is one
    if text:match("\\N") then
	text=text:gsub("%s?\\[Nn]%s?"," ")
    else
	
	text=text:gsub("([%.,%?!])%s$","%1") 
	
	nocom=text:gsub("{[^}]-}","")	nocomlength=nocom:len()
	tags=text:match("^{\\[^}]-}")
	if tags==nil then tags="" end
	stekst=text	:gsub("^{\\[^}]-}","")
	repeat stekst=stekst:gsub("{[^\\}]-}$","") until not stekst:match("{[^\\}]-}$")
	tekst=stekst
	-- fill spaces in comments
	for s in tekst:gmatch("{[^\\}]-}") do
	s2=s:gsub(" ","__")	s=esc(s)	tekst=tekst:gsub(s,s2)
	end
	
	-- get max width of a line in pixels
	width,height,descent,ext_lead=aegisub.text_extents(styleref,nocom)
	xres,yres,ar,artype=aegisub.video_size()
	if xres==nil then xres=resx yres=resy end
	realx=xres/yres*resy
	wf=realx/resx
	if line.style=="Default" then vidth=realx-(defleft*wf)-(defright*wf)
	else vidth=realx-(styleref.margin_l*wf)-(styleref.margin_r*wf) end

	-- count words
	wrd=0	for word in nocom:gmatch("[^%s]+") do wrd=wrd+1 end

	--aegisub.log("\n text - "..tekst)

	    -- put breaks after . , ? ! that are not at the end
	    tekst=tekst:gsub("([^%.])%.%s","%1. \\N")
	    :gsub("([^%.])%.({\\[^}]-})%s","%1.%2 \\N")
	    :gsub("([,!%?:;])%s","%1 \\N")
	    :gsub("([,!%?:;])({\\[^}]-})%s","%1%2 \\N")
	    :gsub("([%.,])\"%s","%1\" \\N")
	    :gsub("%.%.%.%s","... \\N")
	    :gsub("([DM]rs?%.) \\N","%1 ")

	    -- remove comma breaks if . or ? or !
	    if tekst:match("[%.%?!] \\N") and tekst:match(", \\N") then tekst=tekst:gsub(", \\N",", ") end
	    
	    tekst=reduce(tekst)		-- remove breaks if there are more than one; leave the one closer to the centre
	    tekst=balance(tekst)	-- balance of lines - ratio check 1
	    
	    -- if breaks removed and there's a comma
	    if not tekst:match("\\N") then 
	        tekst=tekst:gsub(",%s",", \\N") :gsub(",({\\[^}]-})%s",",%1 \\N") 
		:gsub("^([%w']+, )\\N","%1") :gsub(", \\N([%w%p]+)$",", %1") end
	    tekst=reduce(tekst)
	    
	    -- balance of lines - ratio check 2
	    ratio=nil	tekst=balance(tekst)	backup1=nil
	    if tekst:match("\\N") and ratio~=nil and ratio>=2 and max_ratio>ratio then 
	    backup1=tekst ratio1=ratio  tekst=db(tekst) end

	    if wrd>5 then testxt=tekst:gsub("^[%w%p]+ [%w%p]+(.-)[%w%p]+ [%w%p]+$","%1") else testxt=tekst end

	    -- if no linebreak in line, put breaks before selected words, in 3 rounds
	    words1={" but "," and "," if "," when "," because "," 'cause "," yet "," unless "," with "," without "," whether "}
	    words2={" or "," nor "," for "," from "," before "," at "," that "," since "," until "," while "," behind "," than "}
	    words3={" about "," into "," to "," is "," isn't "," was "," wasn't "," are "," aren't "," were "," weren't "}
	    tekst=words(words1)
	    tekst=words(words2)
	    tekst=words(words3)

	    -- insert break in the middle of the line
	    if force_breaks_in_middle then tekst=db(tekst) end
	    if put_break_in_the_middle and nocomlength>=middle_min_characters and not tekst:match("\\N") then
		tekst="\\N"..tekst
		diff=250	stop=0
		while stop==0 do
		  last=tekst
		  repeat tekst=tekst:gsub("\\N({[^}]-})","%1\\N") tekst=tekst:gsub("\\N([^%s{}]+)","%1\\N")
		  until not tekst:match("\\N{[^}]-}") and not tekst:match("\\N([^%s{}]+)")
		  tekst=tekst:gsub("\\N%s"," \\N")
		  btxt=tekst:gsub("{[^}]-}","")
		  beforespace=btxt:match("^(.-)\\N")	beforelength=beforespace:len()
		  afterspace=btxt:match("\\N(.-)$")	afterlength=afterspace:len()
		  tdiff=math.abs(beforelength-afterlength)
		  if tdiff<diff then diff=tdiff else 
		    stop=1 tekst=last 
		  end
		end
	    end
	    
	    -- shift breaks to better places
	    backup2=tekst
	    tekst=re.sub(tekst," (a|a[sn]|by|I|I'm|I'd|I've|I'll|the|for|that|o[nfr]|i[nf]|who|to) \\\\N([\\w\\-']+) "," \\\\N\\1 \\2 ")
	    tekst=re.sub(tekst," \\\\N([oi]n) (because|and|but|when) "," \\1 \\\\N\\2 ")
	    tekst=tekst
	    :gsub(" lot(s?) \\Nof "," lot%1 of \\N")
	    :gsub(" \\Nme "," me \\N")
	    :gsub("^ ","")
	    --aegisub.log("\n tekst "..tekst)
	    tekstb=balance(tekst)
	    if tekstb~=tekst then tekst=backup2 end
	    
	    double={"so that","no one","ought to","now that","it was","he was","she was","will be","there is","there are","there was","there were","get to","sort of","kind of","put it","each other","each other's","have to","has to","had to","having to","want to","wanted to","used to","able to","going to","supposed to","allowed to","tend to","due to","forward to","thanks to","not to","has been","have been","had been","filled with","full of","out of","into the","onto the","part with","more than","less than","even if","make sure","give up","would be","wipe out","wiped out","real life","no matter","based on","bring up","think of","thought of"}
	    for d=1,#double do
		dbl=double[d]
		d1,d2=dbl:match("([%a']+) ([%a']+)")
		btxt=tekst:gsub("{[^}]-}","")
		if tekst:match(" "..d1.." \\N"..d2.." ") then
		    bd=btxt:match("^(.-)"..d1.." \\N"..d2)	bd=bd:gsub("{[^}]-}","")	blgth=bd:len()
		    ad=btxt:match(d1.." \\N"..d2.."(.-)$")	ad=ad:gsub("{[^}]-}","")	algth=ad:len()
		    if blgth>algth then tekst=tekst:gsub(" "..d1.." \\N"..d2.." "," \\N"..d1.." "..d2.." ") 
		    else tekst=tekst:gsub(" "..d1.." \\N"..d2.." "," "..d1.." "..d2.." \\N") end
		end
	    end
	    tekst=re.sub(tekst," (a|a[sn]|by|I|I'm|I'd|I've|I'll|the|for|o[nfr]|i[nf]|who) \\\\N([\\w\\-']+) "," \\\\N\\1 \\2 ")
	    if tekst:match(" by %a+ing \\N") then
		beforethat=tekst:match("^(.-)by %a+ing \\N")	beforethat=beforethat:gsub("{[^}]-}","")	befrlgth=beforethat:len()
		afterthat=tekst:match("by %a+ing \\N(.-)$")	afterthat=afterthat:gsub("{[^}]-}","")		afterlgth=afterthat:len()
		if befrlgth>afterlgth then tekst=tekst:gsub(" (by %a+ing) \\N"," \\N%1 ") end
	    end
	    
	    if not tekst:match("\\N") and backup1~=nil then tekst=backup1 end
	    if tekst:match("\\N") and backup1~=nil and ratio>=ratio1 then tekst=backup1 end

	    -- character/word restrictions
	    if nocomlength<min_characters or wrd<min_words then tekst=db(tekst) end

	    -- break if there are only 2 words in the line
	    if wrd==2 and allow_break_between_two then tekst=tekst:gsub("(%w+%p?)%s(%w+%p?)%s?","%1 \\N%2") end
	    
	    -- don't break 1-liners if in settings
	    if do_not_break_1liners and vidth>=width then tekst=db(tekst) end

	-- apply changes
	tekst=tekst:gsub("__"," ")
	stekst=esc(stekst)
	text=text:gsub(stekst,tekst)
	
	    -- GUI for manual breaking
	    if disable_dialog==false and not do_not_break_1liners and not text:match("\\N") then
		after=text:gsub("^{\\[^}]-}","")
		dialog=
		{
		    {x=0,y=0,width=25,height=4,class="textbox",name="txt",value=after},
		    {x=0,y=4,width=25,height=1,class="label",label="Use 'Enter' to make linebreaks"},
		} 
		buttons={"OK","All spaces","Cancel"}
		pressed,res=aegisub.dialog.display(dialog,buttons,{close='Cancel'})
		if pressed=="OK" then
		res.txt=res.txt:gsub("\n","\\N") :gsub("\\N "," \\N")
		text=tags..res.txt
		end
		if pressed=="All spaces" then res.txt=res.txt:gsub("%s+"," \\N") text=tags..res.txt end
	    end
    end

    line.text=text
    subs[i]=line
  end
  aegisub.set_undo_point(script_name)
  return sel
end

function balance(tekst)
    if do_balance_checks and tekst:match("\\N") and not tekst:match("\\N%-") and wrd>4 then
	beforespace=tekst:match("^(.-)\\N")	beforespace=beforespace:gsub("{[^}]-}","")	beforelength=beforespace:len()
	afterspace=tekst:match("\\N(.-)$")	afterspace=afterspace:gsub("{[^}]-}","")	afterlength=afterspace:len()
	if beforelength>afterlength then ratio=beforelength/afterlength else ratio=afterlength/beforelength end
	difflength=math.abs(beforelength-afterlength)
	wb=aegisub.text_extents(styleref,beforespace)
	wa=aegisub.text_extents(styleref,afterspace)
	if wb>wa then ratiop=wb/wa else ratiop=wa/wb end
	if ratio>max_ratio then tekst=db(tekst) end
	if nocomlength>50 and ratio>(max_ratio*0.95) or ratiop>(max_ratio*0.95) then tekst=db(tekst) end
	if nocomlength>70 and ratio>(max_ratio*0.9) or ratiop>(max_ratio*0.9) then tekst=db(tekst) end
	    --aegisub.log("\n ratio: "..ratio.."     length: "..nocomlength)    aegisub.log("\n ratiop: "..ratiop)
      -- prevent 3-liners
	if wb>=vidth or wa>=vidth then tekst=db(tekst) end
    end
    return tekst
end

function reduce(tekst)
    if tekst:match("\\N.+\\N") then repeat
	beforespace,afterspace=tekst:match("^(.-)\\N.*\\N(.-)$")
	beforespace=beforespace:gsub("{[^}]-}","")	beforelength=beforespace:len()
	afterspace=afterspace:gsub("{[^}]-}","")	afterlength=afterspace:len()
	if beforelength>afterlength then tekst=tekst:gsub("^(.*)\\N(.-)$","%1%2") else tekst=tekst:gsub("^(.-)\\N","%1") end
    until not tekst:match("\\N.+\\N") 
    end
    return tekst
end

function words(tab)
    if not tekst:match("\\N") and wrd>4 then 
	for w=1,#tab do ord=tab[w]
	  if testxt:match(ord) then tekst=tekst:gsub(ord," \\N"..ord) :gsub("\\N ","\\N") end
	end
	tekst=reduce(tekst)
	tekst=balance(tekst)
    end
    return tekst
end

function db(t) t=t:gsub("\\N","") return t end

function stylechk(subs,stylename)
  for i=1, #subs do
    if subs[i].class=="style" then
      local st=subs[i]
      if stylename==st.name then styleref=st break end
    end
  end
  return styleref
end

function nshift(subs, sel)
    for x, i in ipairs(sel) do
        local line=subs[i]
        local text=line.text
	text=text:gsub("([%a%p])\\N([%a%p])","%1 \\N%2") 
	    if not text:match("\\N") then text="\\N"..text end
		text=text:gsub("\\N([^%s{}]+%s?)$","%1")		-- end
		text=text:gsub("\\N([^%s{}]+%s?{[^}]-}%s?)$","%1") 	-- end
		text=text:gsub("\\N%s"," \\N")
		repeat text=text:gsub("\\N({[^}]-})","%1\\N") text=text:gsub("\\N([^%s{}]+)","%1\\N")
		until not text:match("\\N{[^}]-}") and not text:match("\\N([^%s{}]+)")
		text=text:gsub("\\N%s"," \\N")
		text=text:gsub("\\N$","")
	line.text=text
	subs[i]=line
    end
    aegisub.set_undo_point(script_name)
    return sel
end

function backshift(subs, sel)
    for x, i in ipairs(sel) do
        local line=subs[i]
        local text=line.text
	text=text:gsub("([%a%p])\\N([%a%p])","%1 \\N%2") 
	    if not text:match("\\N") then text=text.."\\N" end
		text=text:gsub("^({[^}]-}%s?[^%s{}]+%s?)\\N","%1")	-- start
		text=text:gsub("^([^%s{}]+%s?)\\N","%1")		-- start
		text=text:gsub("%s\\N","\\N ")
		repeat text=text:gsub("({[^}]-})\\N","\\N%1") text=text:gsub("([^%s{}]+)\\N","\\N%1")
		until not text:match("({[^}]-})\\N") and not text:match("([^%s{}]+)\\N")
		text=text:gsub("^\\N","")
	line.text=text
	subs[i]=line
    end
    aegisub.set_undo_point(script_name)
    return sel
end

aegisub.register_macro("Line Breaker/Insert Linebreak", script_description, nnn)
aegisub.register_macro("Line Breaker/Shift Linebreak", script_description, nshift)
if enable_shift_backwards then aegisub.register_macro("Line Breaker/Shift Linebreak Back", script_description, backshift) end
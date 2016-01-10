local lcmark = require('lcmark')
local cmark = require('cmark')

local trim = function(s)
  return s:gsub("^%s+",""):gsub("%s+$","")
end

local warn = function(s)
  io.stderr:write('WARNING: ' .. s .. '\n')
end

local to_identifier = function(s)
  return trim(s):lower():gsub('[^%w]+', ' '):gsub('[%s]+', '-')
end

local render_number = function(tbl)
  local buf = {}
  for i,x in ipairs(tbl) do
    buf[i] = tostring(x)
  end
  return table.concat(buf, '.')
end

local extract_references = function(doc)
  local cur, entering, node_type
  local refs = {}
  for cur, entering, node_type in cmark.walk(doc) do
    if not entering and
        ((node_type == cmark.NODE_LINK and cmark.node_get_url(cur) == '@') or
          node_type == cmark.NODE_HEADING) then
      local children = cmark.node_first_child(cur)
      local label = trim(cmark.render_commonmark(children, OPT_DEFAULT, 0))
      local ident = to_identifier(label)
      if refs[label] then
        warn("duplicate reference " .. label)
      end
      refs[label] = ident
    end
  end
  return refs
end

local make_toc = function(toc)
  -- we create a commonmark string, then parse it
  local toclines = {}
  for _,entry in ipairs(toc) do
    if entry.level <= 2 then
      local indent = string.rep('    ', entry.level - 1)
      toclines[#toclines + 1] = indent .. '* [' ..
        (entry.number == '' and ''
          or '<span class="number">' .. entry.number .. '</span> ') ..
         entry.label ..  '](#' .. entry.ident .. ')'
    end
  end
  -- now parse our cm list and return the resulting list node:
  local doc = cmark.parse_string(table.concat(toclines, '\n'), cmark.OPT_SMART)
  return cmark.node_first_child(doc)
end

local make_html_element = function(block, tagname, attrs)
  local div = cmark.node_new(block and cmark.NODE_CUSTOM_BLOCK or
                                cmark.NODE_CUSTOM_INLINE)
  local attribs = {}
  for _,attr in ipairs(attrs) do
    attribs[#attribs + 1] = ' ' .. attr[1] .. '="' .. attr[2] .. '"'
  end
  local opentag = '<' .. tagname .. table.concat(attribs, '') .. '>'
  local closetag = '</' .. tagname .. '>'
  cmark.node_set_on_enter(div, opentag)
  cmark.node_set_on_exit(div, closetag)
  return div
end

local make_html_block = function(tagname, attrs)
  return make_html_element(true, tagname, attrs)
end

local make_html_inline = function(tagname, attrs)
  return make_html_element(false, tagname, attrs)
end

local make_text = function(s)
  local text = cmark.node_new(cmark.NODE_TEXT)
  cmark.node_set_literal(text, s)
  return text
end

local create_anchors = function(doc, meta, to)
  local cur, entering, node_type
  local toc = {}
  local number = {0}
  local example = 0
  for cur, entering, node_type in cmark.walk(doc) do
    if not entering and
        ((node_type == cmark.NODE_LINK and cmark.node_get_url(cur) == '@') or
          node_type == cmark.NODE_HEADING) then
      local anchor = cmark.node_new(
        node_type == cmark.NODE_LINK and cmark.NODE_CUSTOM_INLINE or
        cmark.NODE_CUSTOM_BLOCK)
      local children = cmark.node_first_child(cur)
      local label = trim(cmark.render_commonmark(children, OPT_DEFAULT, 0))
      local ident = to_identifier(label)
      if node_type == cmark.NODE_LINK then
        cmark.node_set_on_enter(anchor, '<a id="' .. ident .. '"' ..
               ' href="#' .. ident .. '" class="definition">')
        cmark.node_set_on_exit(anchor, "</a>")
      else -- NODE_HEADING
        local level = cmark.node_get_heading_level(cur)
        local last_level = #toc == 0 and 1 or toc[#toc].level
        if #number > 0 then
          if level > last_level then -- subhead
            number[level] = 1
          else
            while last_level > level do
              number[last_level] = nil
              last_level = last_level - 1
            end
            number[level] = number[level] + 1
          end
        end
        table.insert(toc, { label = label, ident = ident, level = level, number = render_number(number) })
        local num = render_number(number)
        cmark.node_set_on_enter(anchor, '<h' ..
           tostring(level) .. ' id="' .. ident ..  '">' ..
           (num == '' and '' or '<span class="number">' .. num .. '</span> '))
        cmark.node_set_on_exit(anchor, '</h' .. tostring(level) .. '>')
      end
      while children do
        node_append_child(anchor, children)
        children = cmark.node_next(children)
      end
      cmark.node_insert_before(cur, anchor)
      cmark.node_unlink(cur)
    elseif entering and node_type == cmark.NODE_CODE_BLOCK and
          cmark.node_get_fence_info(cur) == 'example' then
      example = example + 1
       -- split into two code blocks
      local code = cmark.node_get_literal(cur)
      local sepstart, sepend = code:find("[\n\r]+%.[\n\r]+")
      if not sepstart then
        warn("Could not find separator in:\n" .. contents)
      end
      local markdown_code = cmark.node_new(cmark.NODE_CODE_BLOCK)
      local html_code = cmark.node_new(cmark.NODE_CODE_BLOCK)
      cmark.node_set_literal(markdown_code, code:sub(1, sepstart))
      cmark.node_set_literal(html_code, code:sub(sepend + 1))
      local leftcol_div = make_html_block('div', {{'class','column'}})
      local rightcol_div = make_html_block('div', {{'class', 'column'}})
      cmark.node_append_child(leftcol_div, markdown_code)
      cmark.node_append_child(rightcol_div, html_code)
      local examplenum_div = make_html_block('div', {{'class', 'examplenum'}})
      local interact_link = make_html_inline('a', {{'class', 'dingus'},
                  {'title', 'open in interactive dingus'}})
      cmark.node_append_child(interact_link, make_text("(interact)"))
      local examplenum_link = cmark.node_new(cmark.NODE_LINK)
      cmark.node_set_url(examplenum_link, '#example-' .. tostring(example))
      cmark.node_append_child(examplenum_link,
                              make_text("Example " .. tostring(example)))
      cmark.node_append_child(examplenum_div, examplenum_link)
      cmark.node_append_child(examplenum_div, make_text("  "))
      cmark.node_append_child(examplenum_div, interact_link)
      local example_div = make_html_block('div', {{'class', 'example'},
                               {'id','example-' .. tostring(example)}})
      cmark.node_append_child(example_div, examplenum_div)
      cmark.node_append_child(example_div, leftcol_div)
      cmark.node_append_child(example_div, rightcol_div)
      cmark.node_insert_before(cur, example_div)
      cmark.node_unlink(cur)
      cmark.node_free(cur)
    elseif node_type == cmark.NODE_HTML_BLOCK and
            cmark.node_get_literal(cur) == '<!-- END TESTS -->\n' then
      -- change numbering
      number = {}
      local appendices = make_html_block('div', {{'class','appendices'}})
      cmark.node_insert_after(cur, appendices)
      -- put the remaining sections in an appendix
      local tmp = cmark.node_next(appendices)
      while tmp do
        cmark.node_append_child(appendices, tmp)
        tmp = cmark.node_next(tmp)
      end
    end
  end
  meta.toc = make_toc(toc)
end

local to_ref = function(ref)
  return '[' .. ref.label .. ']: #' .. ref.indent .. '\n'
end

format = 'html'

io.input("spec.txt")
local inp = io.read("*a")
local doc1 = cmark.parse_string(inp, cmark.OPT_DEFAULT)
local refs = extract_references(doc1)
local refblock = '\n'
for lab,ident in pairs(refs) do
  refblock = refblock .. '[' .. lab .. ']: #' .. ident .. '\n'
  -- refblock = refblock .. '[' .. lab .. 's]: #' .. ident .. '\n'
end
-- append references and parse again
local html, meta, msg  = lcmark.convert(inp .. refblock, format,
                             { smart = true,
                               yaml_metadata = true,
                               safe = false,
                               filters = { create_anchors }
                             })

if html then
  local f = io.open("tools/template.html", 'r')
  if not f then
    io.write("Could not find template!")
    os.exit(1)
  end
  local template = f:read("*a")
  meta.body = html
  local rendered, msg = lcmark.render_template(template, meta)
  if not rendered then
    io.write(msg)
    os.exit(1)
  end
  io.write(rendered)
  os.exit(0)
else
  io.write(msg)
  os.exit(1)
end


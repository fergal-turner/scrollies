-- sc-scrolly layout filter
--
--   ::: {.full}                          full-width text block
--   ::: {.step fig="path" alt="..." caption="..." height="480"}
--                                        text on the left, figure on the right
--   ::: {.highlight}                     red rounded highlight box
--   ::: {.headline align="left|right|center" bg="biscuit|red|none" logo="true"}
--                                        Oswald headline in white text bars
--
-- Top-level YAML option:  sc-logo: colour (default) | white | black | none
--
-- fig may be a .html file (e.g. plotly write_html output, inlined via iframe
-- srcdoc) or an image (.png, .jpg, .svg). Paths are relative to the .qmd.

local LOGOS = {
  colour = 'logos/CH2102039_STC_Logo_Eng_Horiz_ColPos_RGB.svg',
  white = 'logos/CH2102036_STC_Logo_Eng_Horiz_Wht_RGB.svg',
  black = 'logos/CH2102026_STC_Logo_Eng_Horiz_Blk_RGB.svg',
}

local function read_file(path)
  local f = io.open(path, 'rb')
  if not f then return nil end
  local content = f:read('*a')
  f:close()
  return content
end

local function html_attr_escape(s)
  s = s:gsub('&', '&amp;')
  s = s:gsub('"', '&quot;')
  return s
end

local function html_text_escape(s)
  s = s:gsub('&', '&amp;')
  s = s:gsub('<', '&lt;')
  s = s:gsub('>', '&gt;')
  return s
end

-- Logo files ship inside the extension; returns an <img> tag with the SVG as a data URI
local function logo_img(variant, css_class)
  local rel = LOGOS[variant]
  if not rel then return nil end
  local svg = read_file(quarto.utils.resolve_path(rel))
  if not svg then
    io.stderr:write('[sc-scrolly] logo not found: ' .. rel .. '\n')
    return nil
  end
  local encoded = svg:gsub('[^%w%-%._~]', function(c) return string.format('%%%02X', c:byte()) end)
  return string.format('<img class="%s" alt="Save the Children" src="data:image/svg+xml,%s">',
    css_class, encoded)
end

function Meta(meta)
  local variant = meta['sc-logo'] and pandoc.utils.stringify(meta['sc-logo']) or 'colour'
  if variant == 'none' then return nil end
  local img = logo_img(variant, 'sc-logo')
  if img then
    local bar_class = variant == 'white' and 'sc-topbar sc-topbar-dark' or 'sc-topbar'
    quarto.doc.include_text('before-body',
      '<header class="' .. bar_class .. '"><div class="sc-topbar-inner">' .. img .. '</div></header>')
  end
end

local function resolve(path)
  local input = quarto.doc.input_file
  if input then
    local candidate = pandoc.path.join({ pandoc.path.directory(input), path })
    if read_file(candidate) then return candidate end
  end
  return path
end

local function figure_blocks(el)
  local fig = el.attributes['fig']
  if not fig or fig == '' then return {} end

  local alt = el.attributes['alt'] or ''
  local caption = el.attributes['caption']
  local height = el.attributes['height'] or '480'
  local blocks = {}

  if fig:lower():match('%.html?$') then
    local content = read_file(resolve(fig))
    if not content then
      io.stderr:write('[sc-scrolly] figure not found: ' .. fig .. '\n')
      content = '<p style="font-family:sans-serif">Figure not found: ' .. fig .. '</p>'
    end
    -- remove body margin/scrollbars that plotly's standalone html adds
    content = '<style>html,body{margin:0;padding:0;overflow:hidden}</style>' .. content
    -- use the figure's own layout height (last "height":N in the file) so it is rendered at
    -- native size inside the iframe and then scaled to fit by scrolly.html
    local native_h
    for h in content:gmatch('"height":(%d+)') do native_h = h end
    height = native_h or height
    blocks[#blocks + 1] = pandoc.RawBlock('html',
      string.format(
        '<div class="sc-iframe-wrap" data-w="1100" data-h="%s"><iframe class="sc-iframe" title="%s" style="width:1100px;height:%spx" srcdoc="%s"></iframe></div>',
        height, html_attr_escape(alt), height, html_attr_escape(content)))
  else
    local img = pandoc.Image({}, fig, '', pandoc.Attr('', {}, { alt = alt }))
    blocks[#blocks + 1] = pandoc.Plain({ img })
  end

  if caption and caption ~= '' then
    blocks[#blocks + 1] = pandoc.RawBlock('html',
      '<p class="sc-caption">' .. html_attr_escape(caption) .. '</p>')
  end
  return blocks
end

-- Split headline content into lines (paragraph, line and soft breaks all start a new bar)
local function headline_lines(el)
  local lines = {}
  local current = {}
  local function flush()
    if #current > 0 then
      local text = pandoc.utils.stringify(pandoc.Inlines(current))
      if text ~= '' then lines[#lines + 1] = text end
    end
    current = {}
  end
  for _, block in ipairs(el.content) do
    if block.t == 'Para' or block.t == 'Plain' then
      for _, inline in ipairs(block.content) do
        if inline.t == 'LineBreak' or inline.t == 'SoftBreak' then
          flush()
        else
          current[#current + 1] = inline
        end
      end
      flush()
    end
  end
  return lines
end

local function headline_block(el)
  local align = el.attributes['align'] or 'left'
  local bg = el.attributes['bg'] or 'biscuit'
  local parts = {}
  for _, line in ipairs(headline_lines(el)) do
    parts[#parts + 1] = '<span class="sc-hl-line">' .. html_text_escape(line) .. '</span>'
  end
  if el.attributes['logo'] == 'true' then
    local img = logo_img('colour', 'sc-hl-logo-img')
    if img then parts[#parts + 1] = '<span class="sc-hl-logo">' .. img .. '</span>' end
  end
  local html = string.format(
    '<div class="sc-block sc-headline"><div class="sc-hl-band sc-bg-%s sc-align-%s">%s</div></div>',
    bg, align, table.concat(parts))
  return pandoc.RawBlock('html', html)
end

function Div(el)
  if el.classes:includes('full') then
    local inner = pandoc.Div(el.content, pandoc.Attr('', { 'sc-inner' }))
    return pandoc.Div({ inner }, pandoc.Attr(el.identifier, { 'sc-block', 'sc-full' }))
  end

  if el.classes:includes('step') then
    local text = pandoc.Div(el.content, pandoc.Attr('', { 'sc-text' }))
    local fig_inner = pandoc.Div(figure_blocks(el), pandoc.Attr('', { 'sc-fig-inner' }))
    local fig = pandoc.Div({ fig_inner }, pandoc.Attr('', { 'sc-fig' }))
    return pandoc.Div({ text, fig }, pandoc.Attr(el.identifier, { 'sc-block', 'sc-step' }))
  end

  if el.classes:includes('headline') then
    return headline_block(el)
  end
end

-- Top-level highlight boxes get the page container; ones nested in .full/.step don't need it
function Pandoc(doc)
  local blocks = {}
  for _, block in ipairs(doc.blocks) do
    if block.t == 'Div' and block.classes:includes('highlight') then
      blocks[#blocks + 1] = pandoc.Div({ block }, pandoc.Attr('', { 'sc-block' }))
    else
      blocks[#blocks + 1] = block
    end
  end
  doc.blocks = blocks
  return doc
end

sourceMap = require('source-map')
postcss   = require('../lib/postcss')
fs        = require('fs-extra')

describe 'source maps', ->
  before ->
    @dir = __dirname + '/fixtures'

    @doubler = postcss (css) ->
      css.eachDecl (decl) -> decl.parent.prepend(decl.clone())
    @lighter = postcss (css) ->
      css.eachDecl (decl) -> decl.value = 'white'

  afterEach ->
    fs.removeSync(@dir) if fs.existsSync(@dir)

  it 'adds map field only on request', ->
    postcss().process('a {}').should.not.have.property('map')

  it 'generate right source map', ->
    css       = "a {\n  color: black;\n  }"
    processor = postcss (css) ->
      css.eachRule (rule) ->
        rule.selector = 'strong'
      css.eachDecl (decl) ->
        changed = decl.clone(prop: 'background')
        decl.parent.prepend(changed)

    result = processor.process(css, from: 'a.css', to: 'b.css', map: true)
    map    = new sourceMap.SourceMapConsumer(result.map)

    map.file.should.eql('b.css')

    map.originalPositionFor(line: 1, column: 0).should.eql
      source: 'a.css'
      line:   1
      column: 0
      name:   null
    map.originalPositionFor(line: 2, column: 2).should.eql
      source: 'a.css'
      line:   2
      column: 2
      name:   null
    map.originalPositionFor(line: 3, column: 2).should.eql
      source: 'a.css'
      line:   2
      column: 2
      name:   null

  it 'changes previous source map', ->
    css = 'a { color: black }'

    doubled = @doubler.process css,
      from: 'a.css'
      to:   'b.css'
      map:  true

    lighted = @lighter.process doubled.css,
      from: 'b.css'
      to:   'c.css'
      map:  doubled.map

    map = new sourceMap.SourceMapConsumer(lighted.map)

    map.originalPositionFor(line: 1, column: 18).should.eql
      source: 'a.css'
      line:   1
      column: 4
      name:   null

  it 'adds source map annotation', ->
    css    = 'a { }/*# sourceMappingURL=a.css.map */'
    result = postcss().process css,
      from: 'a.css'
      to:   'b.css'
      map:  true

    result.css.should.eql "a { }\n/*# sourceMappingURL=b.css.map */"

  it 'misses source map annotation, if user ask', ->
    css    = 'a { }'
    result = postcss().process css,
      from:         'a.css'
      to:           'b.css'
      map:           true
      mapAnnotation: false

    result.css.should.eql(css)

  it 'misses source map annotation, if previous map missed it', ->
    css = 'a { }'

    step1 = postcss().process css,
      from:         'a.css'
      to:           'b.css'
      map:           true
      mapAnnotation: false

    step2 = postcss().process step1.css,
      from: 'b.css'
      to:   'c.css'
      map:  step1.map

    step2.css.should.eql(css)

  it 'generates inline map', ->
    css = 'a { }'

    common = postcss().process css,
      from: 'a.css'
      to:   'b.css'
      map:   true

    inline = postcss().process css,
      from:     'a.css'
      to:       'b.css'
      inlineMap: true

    inline.should.not.have.property('map')
    inline.css.should.match(/# sourceMappingURL=data:/)

    base64 = new Buffer(common.map).toString('base64')
    inline.css.should.endWith(base64 + ' */')

  it 'generates inline map if previous map was inline', ->
    css     = 'a { color: black }'

    common1 = @doubler.process css,
      from: 'a.css'
      to:   'b.css'
      map:   true
    common2 = @lighter.process common1.css,
      from: 'b.css'
      to:   'c.css'
      map:   common1.map

    inline1 = @doubler.process css,
      from:     'a.css'
      to:       'b.css'
      inlineMap: true
    inline2 = @lighter.process inline1.css,
      from: 'b.css'
      to:   'c.css'

    base64 = new Buffer(common2.map).toString('base64')
    inline2.css.should.endWith(base64 + ' */')

  it 'allows change map type', ->
    css = 'a { }'

    step1 = postcss().process css,
      from:     'a.css'
      to:       'b.css'
      inlineMap: true

    step2 = postcss().process step1.css,
      from:     'b.css'
      to:       'c.css'
      inlineMap: false

    step2.should.have.property('map')
    step2.css.should.not.match(/# sourceMappingURL=data:/)

  it 'checks map file near CSS', ->
    step1 = @doubler.process 'a { }',
      from: 'a.css'
      to:    @dir + '/a.css'
      map:   true

    fs.outputFileSync(@dir + '/a.css.map', step1.map)
    step2 = @lighter.process step1.css,
      from: @dir + '/a.css'
      to:  'b.css'

    step2.should.have.property('map')

  it 'read map file from annotation', ->
    step1 = @doubler.process 'a { }',
      from: 'a.css'
      to:    @dir + '/a.css'
      map:   true

    fs.outputFileSync(@dir + '/b.css.map', step1.map)
    css = step1.css.replace('a.css.map', 'b.css.map')

    step2 = @lighter.process css,
      from: @dir + '/a.css'
      to:  'c.css'

    step2.should.have.property('map')

  it 'miss check files on requires', ->
    step1 = @doubler.process 'a { }',
      from: 'a.css'
      to:    @dir + '/a.css'
      map:   true

    fs.outputFileSync(@dir + '/a.css.map', step1.map)
    step2 = @lighter.process step1.css,
      from: @dir + '/a.css'
      to:  'b.css'
      map:  false

    step2.should.not.have.property('map')

  it 'uses map from subdir', ->
    step1 = @doubler.process 'a { }',
      from: 'a.css'
      to:   'out/b.css'
      map:   true

    step2 = @doubler.process 'a { }',
      from: 'b.css'
      to:   'c.css'
      map:   step1.map


    map = new sourceMap.SourceMapConsumer(step2.map)
    map.originalPositionFor(line: 1, column: 0).should.eql
      source: 'a.css'
      line:   1
      column: 0
      name:   null

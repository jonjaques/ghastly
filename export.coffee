TIMESTAMP = (new Date()).valueOf()

CONFIG_FILE     = './config/site.json'
PRODUCTS_FILE   = './config/products.json'
ATTRS_FILE      = './config/attributes.json'
EXPORT_DEBUG    = './export/debug.json'
EXPORT_FILE     = "./export/export_#{TIMESTAMP}.json"

DEBUG = true
DEBUG_PRODUCTS = [
  20990, 23509
]

q = require 'q'
fs = require 'fs'
_ = require 'underscore'
utils = require 'utils'

casper = require('casper').create
  verbose: true
  logLevel: if DEBUG then 'info' else 'info'
  viewportSize:
    width: 800
    height: 600

exportData =
  products: []
  errors: []
  scraped: 0
  loaded: 0

unless fs.isReadable PRODUCTS_FILE
  throw "No products file is present."

if DEBUG
  products = DEBUG_PRODUCTS
else
  productsJson = JSON.parse fs.read PRODUCTS_FILE
  products = _.pluck productsJson.data, 'product_id'

exportData.loaded = products.length

unless fs.isReadable ATTRS_FILE
  throw "No attributes file is present."
productAttrs = JSON.parse fs.read ATTRS_FILE

unless fs.isReadable CONFIG_FILE
  throw "No config file is present."
config = JSON.parse fs.read CONFIG_FILE

unless config.url
  throw "Must specify base url."
baseUrl = config.url

exportsJSON = ->
  data = JSON.stringify(exportData, null, 2)
  if DEBUG
    fs.write EXPORT_DEBUG, "\n\n// ---\n// #{TIMESTAMP}\n\n, "+data, 'a'
  else
    fs.write EXPORT_FILE, data, 'w'

doLoginCheck = ->
  @echo "Doing login check"
  loggedIn = if @exists '#loginForm' then false else true
  @echo "User is #{if loggedIn then '' else 'not '}logged in"
  unless loggedIn
    @echo "Filling login form"
    @fill 'form#loginForm',
      "login[username]": config.username
      "login[password]": config.password
    , true
  return loggedIn

isConfigurable = (self)->
  self.exists '#product_info_tabs_configurable'

deserialize = (form)->

  textInput = (attr)=>
    if isConfigurable @
      @getElementAttribute "[name='product[#{attr}]']", 'value'
    else
      form["product[#{attr}]"]

  selectInput = (attr)=>
    if isConfigurable @
      selectVal = @getElementAttribute "[name='product[#{attr}]']", 'value'
    else
      selectVal = form["product[#{attr}]"]
    if selectVal and selectVal.length
      return @fetchText "##{attr} option[value='#{selectVal}']"
    else
      return null

  attrObj = {}

  _.map productAttrs, (val, key)=>
    formKey = if val.name? then val.name else key
    if val.type is 'text'
      attrObj[key] = textInput formKey
    else
      attrObj[key] = selectInput formKey

  return attrObj

scrapeProduct = (self, productId)->
  self.thenOpen "#{baseUrl}/index.php/admin/catalog_product/edit/store/0/id/#{productId}/", ->
    try
      form = @getFormValues '#product_edit_form'
      newProduct = deserialize.bind(@)(form)

      # clean up the data a bit
      unless DEBUG
        _.map newProduct, (val, key)->
          if val is null or val.length is 0 then delete newProduct[key]

      exportData.products.push newProduct
      exportData.scraped = exportData.scraped + 1
      exportData.last = newProduct.id
    catch error
      console.log error
      exportData.errors.push
        id: productId
        msg: if error and error.message then error.message else error
        html: @getHTML()


casper.start "#{baseUrl}/index.php/admin", ->
  doLoginCheck.bind(@)()

casper.each products, (self, product)->
  scrapeProduct self, product

casper.then ->
  exportsJSON products

casper.run()
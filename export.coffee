timestamp = (new Date()).valueOf()

CONFIG_FILE = './config.json'
EXPORT_DEBUG = './export/debug.json'
EXPORT_FILE = "./export/export_#{timestamp}.json"
PRODUCTS_FILE = './data/productsEnabled.json'
DEBUG_PRODUCTS = [
	23509, 20990
]

DEBUG = true

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

exportObj = {}
exportObj.products = []
exportObj.errors = []
exportObj.scraped = 0

unless fs.isReadable PRODUCTS_FILE
	throw "No products file is present."

if DEBUG
	productsToScrape = DEBUG_PRODUCTS
else
	products = JSON.parse fs.read PRODUCTS_FILE
	productsToScrape = _.pluck products.data, 'product_id'

exportObj.loaded = productsToScrape.length

unless fs.isReadable CONFIG_FILE
	throw "No config file is present."
config = JSON.parse fs.read CONFIG_FILE

unless config.url
	throw "Must specify base url."
baseUrl = config.url

exportsJSON = ->
	exportData = JSON.stringify(exportObj, null, 2)
	if DEBUG
		fs.write EXPORT_DEBUG, "\n\n// ---\n// #{timestamp}\n\n, "+exportData, 'a'
	else
		fs.write EXPORT_FILE, exportData, 'w'


doLoginCheck = ->
	loggedIn = if @exists '#loginForm' then false else true
	unless loggedIn
		@fill 'form#loginForm',
			"login[username]": config.username
			"login[password]": config.password
		, true
	return loggedIn

deserialize = (form)->

	textInput = (attr)=>
		form["product[#{attr}]"]

	selectInput = (attr)=>
		selectVal = form["product[#{attr}]"]
		if selectVal and selectVal.length
			text = @fetchText "##{attr} option[value='#{selectVal}']"
			return text
		else
			return null

	obj =
		## GENERAL
		name 					: textInput 'name'
		shortDesc 		: textInput 'short_description'
		desc 					: textInput 'description'
		longDesc 			: textInput 'long_description'
		# suggested uses
		sku 					: textInput 'sku'
		weight 				: textInput 'weight'
		status 				: selectInput 'status'
		url_key 			: textInput 'url_key'
		visibility 		: selectInput 'visibility'

		## ATTRS
		amount 						: selectInput 'amount'
		style 						: selectInput 'style'
		size_numeric 			: selectInput 'size_numeric'
		gender 						: selectInput 'gender'
		country_origin 		: selectInput 'country_origin'
		dimensions 				: textInput 'dimensions'
		color 						: selectInput 'color'
		manufacturer 			: selectInput 'manufacturer'
		length 						: selectInput 'length'
		ismonogrammable 	: selectInput 'ismonogrammable'
		condition 				: selectInput 'condition'
		zipper_side 			: selectInput 'zipper_side'

		## IMAGES
		images  							: JSON.parse form["product[media_gallery][images]"]
		images_values  				: JSON.parse form["product[media_gallery][values]"]

		## PRICES
		price 								: textInput 'price'
		special_from_date 		: textInput 'special_from_date'
		special_price 				: textInput 'special_price'
		special_to_date 			: textInput 'special_to_date'
		cost 									: textInput 'cost'
		tax_class_id 					: selectInput 'tax_class_id'

		## META
		meta_keyword 					: selectInput 'meta_keyword'
		meta_description 			: selectInput 'meta_description'
		meta_search_terms 		: textInput 'meta_search_terms'
		meta_title 						: textInput 'meta_title'

		## SHIPPING
		shipping_price: textInput 'shipping_price'
		special_shipping_group: selectInput 'special_shipping_group'


scrapeProduct = (self, productId)->
	self.thenOpen "#{baseUrl}/index.php/admin/catalog_product/edit/store/0/id/#{productId}/", ->
		try
			@waitFor (=> @exists '#product_edit_form'), ()=>
				form = @getFormValues '#product_edit_form'
				unless form?
					throw "Unable to get form values"
				newProduct = deserialize.bind(@)(form)

				# clean up the data a bit
				unless DEBUG
					_.map newProduct, (val, key)->
						if val is null or val.length is 0 then delete newProduct[key]

				exportObj.products.push newProduct
				exportObj.scraped = exportObj.scraped + 1
				exportObj.last = newProduct.id
		catch error
			console.log error
			exportObj.errors.push
				id: productId
				msg: if error and error.message then error.message else error
				html: @getHTML()


casper.start "#{baseUrl}/index.php/admin", ->
	doLoginCheck.bind(@)()

casper.each productsToScrape, (self, product)->
	scrapeProduct self, product

casper.then ->
	exportsJSON products



casper.run()
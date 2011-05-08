/**
 *  Copyright (c)  2011 coltware@gmail.com
 *  http://www.coltware.com 
 *
 *  License: LGPL v3 ( http://www.gnu.org/licenses/lgpl-3.0-standalone.html )
 *
 * @author coltware@gmail.com
 */
package com.coltware.airxlib.db
{
	import flash.data.SQLConnection;
	import flash.data.SQLStatement;
	import flash.errors.IllegalOperationError;
	import flash.events.EventDispatcher;
	import flash.events.SQLErrorEvent;
	import flash.events.SQLEvent;
	import flash.filesystem.File;
	import flash.utils.getDefinitionByName;
	
	import mx.logging.ILogger;
	import mx.logging.Log;
	import mx.rpc.events.FaultEvent;
	import mx.rpc.events.ResultEvent;
	import mx.rpc.http.mxml.HTTPService;
	
	[Event(name="newObject",type="com.coltware.airxlib.db.TableEvent")]
	
    public class DBManager extends EventDispatcher
    {
		private static const $__debug__:Boolean = true;
    	
    	private static var _instance:Object = new Object();
    	private static var _internal:Boolean = false;
    	
    	/**
    	 *  XMLのファイルを管理する
    	 */
    	private var _xmlMap:Object;
    	/**
    	 *  テーブルオブジェクトを管理する
    	 */
    	private var _tableMap:Object;
    	private var _connection:SQLConnection;
    	
    	private var _urlToId:Object;
    	
    	/**
    	 *  IDとクラス名を管理する
    	 */
    	private var _clzMap:Object;
    	
    	private static const _log:ILogger = Log.getLogger("com.coltware.airlib.db.DBManager");
		
        public function DBManager()
        {
        	 if(_internal){
        	 	_xmlMap = new Object();
        	 	_urlToId = new Object();
        	 	_tableMap = new Object();
        	 	_clzMap = new Object();
        	 }
        	 else{
        	 	throw new IllegalOperationError("please call getInstance()");
        	 }
        }
		
		public static function newInstance(conn:SQLConnection, name:String = "_default_db_"):DBManager{
			if(_instance[name]){
				throw new Error("duplicate invoked");
			}
			_internal = true;
			var dbman:DBManager = new DBManager();
			dbman._connection = conn;
			_instance[name] = dbman;
			return dbman;
		}
        
        public static function getInstance(name:String = "_default_db_"):DBManager{
        	if(_instance[name]){
				return _instance[name];
			}
			return null;
        }
		
		public static function setConnection(conn:SQLConnection, name:String = "_default_db_"):void{
			if(_instance[name]){
				var dbman:DBManager = _instance[name] as DBManager;
				dbman._connection = conn;
			}
		}

        /**
        *   
        * @param id   					テーブルオブジェクトを管理するID
        * @param url  					テーブル定義のXML
        * @param createIfNotExist 		テーブルがなかったときにテーブルを作成するか
        * @param tableObjectClass		テーブルオブジェクトのクラス名
        */
        public function registerTable(id:String,url:String,tableObjectClass:Class = null,createIfNotExist:Boolean = true):void{
        	if(tableObjectClass != null){
        		_log.debug("register class => " + id + " => " + tableObjectClass); 
        		this._clzMap[id] = tableObjectClass;
        	}
			this._xmlMap[id] = url;
        	this.createTableModel(id,createIfNotExist);	
        }
        
        public function getConnection():SQLConnection{
        	return this._connection;
        }
        
        public function getTable(id:String):Table{
        	return this.getTableModel(id,false);
        }
        
        public function getTableModel(id:String,createIfNotExist:Boolean = false):Table{
        	if(_tableMap[id]){
        		return _tableMap[id];
        	}
        	_log.info("getTableModel(): not found in cache. " + id);
        	
        	if(this._xmlMap[id] == null){
        		throw new IllegalOperationError(id + " is not fount. please check to call register() function");
        	}
			return null;
        }
        
        private function _handleXMLError(e:FaultEvent):void{
        	_log.fatal("XML error" + e.message);
        }
        
        /**
        *   テーブルオブジェクトを作っておく
        */ 
        public function createTableModel(id:String,createIfNotExist:Boolean = false):void{
			var http:HTTPService = new HTTPService();
			http.resultFormat = "e4x";
			http.useProxy = false;
			http.url = this._xmlMap[id];
			this._urlToId[http.url] = id;
			//http.request["_table.id"] = id;
			if(createIfNotExist){
				http.request["_table.create"] = true;
			}
			http.addEventListener(ResultEvent.RESULT,_handleGetTableModel);
			http.addEventListener(FaultEvent.FAULT,_handleXMLError);
			http.send();
			
			if($__debug__) _log.debug("loading ..." + http.url);
        }
        
        private function _handleGetTableModel(event:ResultEvent):void{
        	var http:Object = event.target;
        	var url:String = http.url;
        	var id:String = this._urlToId[http.url];
        	if($__debug__) 	_log.debug("xml table file " + http.url + " loaded .. (" + id + ")");
        	
        	var xml:XML = http.lastResult as XML;
        	
        	var createIfNot:Boolean = http.request["_table.create"];
        	
        	var className:String = xml.@className;
        	var clz:Class = null;
        	var dbName:String = xml.@db;
        	if(className != null && className.length > 0){
        		if($__debug__) _log.debug("table object is " + className);
        		clz = getDefinitionByName(className) as Class;
        	}
        	
        	if(clz == null){
        		//  クラス名が登録されていないか
        		if($__debug__) _log.debug("class map " + id + " => " + _clzMap[id]);
        		if(_clzMap[id] != null){
        			clz = _clzMap[id] as Class;
        		}
        		else{
        			className = "com.coltware.commons.db.Table";
        			clz = getDefinitionByName(className) as Class;
        		}
        	}
        	
        	var table:Table = new clz();
        	if(dbName != null){
        		_log.debug("dbName is " + dbName);
        		table.sqlConnection = this._connection;
        	}
        	
        	if(createIfNot == true){
        		//  テーブルが作成されていなければ、作成処理をする
        		_log.info("create if not exists table .... invoked");
        		if(this._connection){
        			var factory:TableFactory = new TableFactory();
        			factory.xml = xml;
        			factory.connection = this._connection;
        			factory.create(_handleCreateTable,null,true);
        		}
        	}
        	
        	
        	table.xml = xml;
        	var itemClass:String = xml.@itemClass;
        	if(itemClass != null && itemClass.length > 0){
        		if($__debug__)_log.debug("table default itemClass is " + xml.@itemClass);
        		var itemClz:Class = getDefinitionByName(xml.@itemClass) as Class;
        		table.itemClass = itemClz;
        	}
        	table.create();
        	_tableMap[id] = table;
        	if($__debug__) _log.debug("table object cache :" + id + "/" + _tableMap[id]);
        	var e:TableEvent = new TableEvent(TableEvent.NEW_OBJECT);
        	e.tableObject = table;
        	dispatchEvent(e);
        }
        
        /**
        *   テーブルの作成を行ったときのイベント
        */ 
        private function _handleCreateTable(event:SQLEvent):void{
        	var stmt:SQLStatement = event.target as SQLStatement;
        	_log.info("TABLE CREATE OK ");
        	if($__debug__) _log.debug("[SQL:] " + stmt.text); 
        }
        
    }
}
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
	import flash.data.SQLResult;
	import flash.data.SQLStatement;
	import flash.errors.IllegalOperationError;
	import flash.events.EventDispatcher;
	import flash.events.SQLErrorEvent;
	import flash.events.SQLEvent;
	import flash.utils.getQualifiedClassName;
	
	import mx.collections.ArrayCollection;
	import mx.logging.ILogger;
	import mx.logging.Log;
	import mx.utils.ObjectUtil;
	
	[Event(name="tableInsert",type="com.coltware.airxlib.db.TableEvent")]
	[Event(name="tableUpdate",type="com.coltware.airxlib.db.TableEvent")]
	[Event(name="tableDelete",type="com.coltware.airxlib.db.TableEvent")]
	[Event(name="tableChangeTotal",type="com.coltware.airxlib.db.TableEvent")]
	[Event(name="tableChange",type="com.coltware.airxlib.db.TableEvent")]
	
	public class Table extends EventDispatcher{
		
		private static const $__debug__:Boolean = true;
		private static const _log:ILogger = Log.getLogger("com.coltware.airxlib.db.Table");
		public static var debug:Boolean = false;
		
		protected var _conn:SQLConnection;
		public var tableName:String;
		private var fields:Object;
		private var _xml:XML;
		
		private var _auto_increment_key:String;
		private var _pkey:Array;
		protected var _defaultItemClass:Class = null;
		
		public var lastSql:String = "";
		
		private var _transaction:Boolean = false;
		
		
		/*
		*  テーブルレコード数を保持する
		*/
		private var totalNum:Number;
		
		public static var FIELD_INTEGER:int = 1;
		public static var FIELD_TEXT:int = 2;
		public static var FIELD_DATE:int = 3;
		public static var FIELD_AUTO:int = -1;
		
		protected var _field_created_at:String = null;
		protected var _field_updated_at:String = null;
		
		
		/**
		 * 追加時に自動的にDate情報が入るフィールド
		 */ 
		public function setCreatedAtField(name:String):void{
			_field_created_at = name;
		}
		
		public function setUpdatedAtField(name:String):void{
			_field_updated_at = name;
		}
		
		
		
		/**
		 * 更新時に無視するフィールド
		 */
		private var ignoreUpdateField:ArrayCollection;
		
		public function Table() {
			this.ignoreUpdateField = new ArrayCollection();
			this._pkey = new Array();
			
		}
		public function set itemClass(clz:Class):void{
			this._defaultItemClass = clz;
		}
		
		public function get itemClass():Class{
			return this._defaultItemClass;
		}
		
		public function addUpdateIgnoreField(fname:String):void{
			this.ignoreUpdateField.addItem(fname);
		}
		
		/**
		*
		*/
		public function set sqlConnection(conn:SQLConnection):void{
			this._conn = conn;
		}
		
		public function get sqlConnection():SQLConnection{
			return this._conn;
		}
		/**
		*  定義XMLの設定
		*/
		public function set xml(defxml:XML):void{
			this._xml = defxml;
		}
		
		public function getTableName():String{
			return this.tableName;
		}
		
		public function create():void{
			
			if(this._xml == null){
				throw new IllegalOperationError("xml is null");
			}
			tableName = this._xml.@name;
			fields = new Object();
			for each(var child:XML in this._xml.field){
				var name:String = child.@name;
				var type:String = child.@type;
				if(child.@auto_increment == "true"){
					_auto_increment_key = name;
					fields[name] = FIELD_AUTO;
					_pkey.push(name);
					_log.debug("pkey(auto increment) is " + _pkey);
				}
				else{
					if(child.@primary == "true"){
						_pkey.push(name);
						_log.debug("pkey is " + _pkey);
					}
					fields[name] = getFieldType(type);
				}
				
			}
			this.afterCreate();
		}
		
		public function begin():void{
			this._conn.begin();
			this._transaction = true;
		}
		
		public function commit():void{
			
			if(this._transaction){
				this._conn.commit();
			}
			this._transaction = false;
			
			var evt:TableEvent = new TableEvent(TableEvent.TABLE_CHANGE);
			evt.tableObject = this;
			dispatchEvent(evt);
		}
		
		protected function afterCreate():void{
			
		}
		
		protected function insertBefore(item:Object):void{
			
		}
		
		/**
		 *  登録処理
		 */ 
		public function insertItem(raw:Object,func:Function = null,errorFunc:Function = null):void{
			
			_log.debug("insert item: " + getQualifiedClassName(raw));
			
			var stmt:SQLStatement = new SQLStatement();
			stmt.sqlConnection = _conn;
			
			if(raw == null){
				raw = new Object();
			}
			
			this.insertBefore(raw);
			
			var sql:String = "";
			var flds:Array = new Array();
			var data:Array = new Array();
			for(var fld:String in fields){
				
				if(_field_created_at && fld == _field_created_at){
					data.push(":" + fld);
					flds.push(fld);
					stmt.parameters[":" + fld] = new Date();
				}
				else if(_field_updated_at && fld == _field_updated_at){ 
					data.push(":" + fld);
					flds.push(fld);
					stmt.parameters[":" + fld] = new Date();
				}
				else{
				
				if(fields[fld] > 0 ){
					if(!raw.hasOwnProperty(fld) || raw[fld] == null){
						// 登録時には NULL　は入れずに DBのdefaultに任せる
						//data.push("NULL");
						//flds.push(fld);
					}
					else{
						var k:String = ":" + fld;
						data.push(k);
						flds.push(fld);
						
						stmt.parameters[k] = raw[fld];
						//_log.debug(k + " => " + raw[fld]);
					}
				}
				else{
					if($__debug__) _log.debug("field type is " + fld + ":" + fields[fld]);
				}
				}
			}
			sql = "INSERT INTO " + this.tableName + "\n(" +
			flds.join(",") + ") \n" + "VALUES(" + data.join(",") + ")";
			lastSql = sql;
			stmt.text = sql;
			
			var insertFunc:Function = function():void{
				var result:SQLResult = stmt.getResult();
				
				if(_auto_increment_key){
					var num:Number = result.lastInsertRowID;
					raw[_auto_increment_key] = num;
					
					_log.debug("last insert id : " + num);
					_log.debug("last insert id2 : " + result.lastInsertRowID);
				}
				
				if(func != null){
					func(result);
				}
				if(!_transaction){
					fireInsertEvent(result,raw);
				}
				stmt.removeEventListener(SQLEvent.RESULT,insertFunc);
				stmt.removeEventListener(SQLErrorEvent.ERROR,insertErrorFunc);
			};
			
			var insertErrorFunc:Function = function(errEvt:SQLErrorEvent):void{
				_log.info("DB INSERT ERROR: " + errEvt.text);
				if(errorFunc != null){
					errorFunc(errEvt);
				}
				stmt.removeEventListener(SQLErrorEvent.ERROR,insertErrorFunc);
				stmt.removeEventListener(SQLEvent.RESULT,insertFunc);
			}
			stmt.addEventListener(SQLErrorEvent.ERROR,insertErrorFunc);
			stmt.addEventListener(SQLEvent.RESULT,insertFunc);
			stmt.execute();
		}
		
		/**
		 *  UPDATE ITEM
		 */
		public function updateItem(item:Object,func:Function = null,setNull:Boolean = false):void{
			var stmt:SQLStatement = new SQLStatement();
			stmt.sqlConnection = _conn;
			
			var wheres:Array = new Array();
			var set:Array = new Array();
			
			for(var fieldName:String in fields){
				if(_pkey.indexOf(fieldName) > -1){
					wheres.push(fieldName + "= :" + fieldName);
					stmt.parameters[":" + fieldName] = item[fieldName];
				}
				else if(_field_created_at && fieldName == _field_created_at){
					// skip ...
				}
				else if(_field_updated_at && fieldName == _field_updated_at){
					set.push(fieldName + " = :" + fieldName);
					stmt.parameters[":" + fieldName] = new Date();
				}
				else{
					if(item.hasOwnProperty(fieldName)){
						if(item[fieldName] != null){
							set.push(fieldName + " =:" + fieldName);
							stmt.parameters[":" + fieldName] = item[fieldName];
						}
						else{
							if(setNull){
								set.push(fieldName + " = NULL ");
							}
						}
					}
				}
			}
			
			var sql:String = "UPDATE " + this.tableName + " SET \n" + set.join(",\n") + " WHERE " + wheres.join(" AND ");
			_log.debug("update sql: " + sql);
			lastSql = sql;
			
			stmt.text = sql;
			
			var updateFunc:Function = function():void{
				var result:SQLResult = stmt.getResult();
				if(func != null){
					func(result);
				}
				if(!_transaction){
					fireUpdateEvent(result,item);
				}
				stmt.removeEventListener(SQLEvent.RESULT,updateFunc);
			};
			stmt.addEventListener(SQLEvent.RESULT,updateFunc);
			stmt.execute();
		}
		
		public function updateWhere(data:Object,query:QueryParameter,triggerEvent:Boolean = true):void{
			var stmt:SQLStatement = new SQLStatement();
			stmt.sqlConnection = _conn;
			
			var whereStr:String = "";
			var set:Array = new Array();
			if(query){
				whereStr = this._get_where(stmt,query);
			}
			
			for(var key:String in data){
				stmt.parameters[":_u_" + key] = data[key];
				set.push(key + " = :_u_" + key);
			}
			
			var sql:String = "UPDATE " + this.tableName + "\n" +
				" SET " + set.join(",\n") + whereStr;
			
			if($__debug__)_log.debug("sql: " + sql);
			
			lastSql = sql;
			stmt.text = sql;
			if(triggerEvent){
				var updateFunc:Function = function():void{
					var result:SQLResult = stmt.getResult();
					if(_transaction){
						fireUpdateEvent(result);
					}
					stmt.removeEventListener(SQLEvent.RESULT,updateFunc);
				};
				stmt.addEventListener(SQLEvent.RESULT,updateFunc);
			}
			stmt.execute();
		}
		
		/**
		 *  更新処理
		 */
		/*
		public function updateSync(raw:Object,where:String,setNull:Boolean = false ):SQLStatement{
			var stmt:SQLStatement = new SQLStatement();
			stmt.sqlConnection = _conn;
			stmt.addEventListener(SQLEvent.RESULT,fireUpdateEvent);
			
			if(raw == null){
				throw new IllegalOperationError("update object is NULL");
			}
			if(where == null || where.length < 1 ){
				throw new IllegalOperationError("where arg is NULL");
			}
			
			var sql:String = "";
			var flds:Array = new Array();
			var data:Array = new Array();
			for(var fld:String in fields){
				if(_pkey.indexOf(fld) > -1){
					if(raw[fld] != null){
						stmt.parameters[":" + fld] = raw[fld];
						_log.debug("update [" + fld + "] => " + raw[fld]);
					}
				}
				else if(fld == _field_created_at){
					// -- Do Nothing
				}
				else if(fld == _field_updated_at){
					data.push(fld + " = :" + fld);
					stmt.parameters[":" + fld] = new Date();
				}
				else{
				
				if(fields[fld] > 0 && !this.ignoreUpdateField.contains(fld)){
					if(raw[fld] == null){
						if(setNull == true){
							data.push(fld + " = NULL");
						}
					}
					else{
						data.push(fld + " = :" + fld);
						stmt.parameters[":" + fld] = raw[fld];
						_log.debug("update [" + fld + "] => " + raw[fld]);
					}
				}
				}
			}
			sql = "UPDATE " + this.tableName + "\n" +
			      " SET " + data.join(",\n") + "\n" +
			      " WHERE " + where;
			
			if($__debug__)_log.debug("sql: " + sql);
			
			lastSql = sql;
			stmt.text = sql;
			stmt.execute();
			return stmt;
		}
		*/
		
		/**
		 *  INSERT EVENT
		 */
		protected function fireInsertEvent(result:SQLResult,item:Object = null):void{
			
			_log.debug("fireInserEvent..." + this.tableName);
			
			
			if(this.hasEventListener(TableEvent.INSERT)){
			
				var ne:TableEvent = new TableEvent(TableEvent.INSERT);
				ne.result = result;
				ne.tableObject = this;
				ne.item = item;
				dispatchEvent(ne);
			
			}
			
			if(this.hasEventListener(TableEvent.CHANGE_TOTAL)){
			
				var ch:TableEvent = new TableEvent(TableEvent.CHANGE_TOTAL);
				ch.result = result;
				ch.tableObject = this;
				ch.item = item;
				dispatchEvent(ch);
			}
				
			if(this.hasEventListener(TableEvent.TABLE_CHANGE)){
			
				var evt:TableEvent = new TableEvent(TableEvent.TABLE_CHANGE);
				evt.result = result;
				evt.tableObject = this;
				evt.item = item;
				dispatchEvent(evt);
			
			}
			
			//_log.debug("fireInsertEvent : dispatchInsertEvent - " + result.lastInsertRowID);
		}
		
		protected function fireUpdateEvent(result:SQLResult,item:Object = null):void{
			
			var ne:TableEvent = new TableEvent(TableEvent.UPDATE);
			ne.result = result;
			ne.tableObject = this;
			ne.item = item;
			dispatchEvent(ne);
			
			var chg:TableEvent = new TableEvent(TableEvent.TABLE_CHANGE);
			chg.result = result;
			chg.tableObject = this;
			dispatchEvent(chg);
			
			if($__debug__)_log.debug("dispatchUpdateEvent - " + result.rowsAffected);
		}
		
		/**
		 *  DELETE ITEM
		 */
		public function deleteItem(item:Object,func:Function = null):void{
			var stmt:SQLStatement = new SQLStatement();
			stmt.sqlConnection = this._conn;
			
			var wheres:Array = new Array();
			for(var i:int = 0;  i < this._pkey.length; i++){
				var key:String = _pkey[i];
				_log.debug("delete pkey is :" + key);
				if(item.hasOwnProperty(key)){
					wheres.push(key + " = :" + key);
					stmt.parameters[":" + key] = item[key];
				}
			}
			
			if(wheres.length > 0){
				
				var sql:String = "DELETE FROM " + this.tableName + " WHERE " + wheres.join(" AND ");
				
				stmt.text = sql;
				lastSql = sql;
				_log.debug("DELETE ITEM[" + sql + "]");
				
				var _deleteItemFunc:Function = function():void{
					var result:SQLResult = stmt.getResult();
					if(func != null){
						func(result);
					}
					fireDeleteEvent(result);
					stmt.removeEventListener(SQLEvent.RESULT,_deleteItemFunc);
				};
				stmt.addEventListener(SQLEvent.RESULT,_deleteItemFunc);
				stmt.execute();
			}
			else{
				// TODO エラー処理
			}
		}
		
		/**
		 * 
		 * 削除処理
		 * 
		 */
		public function deleteWhere(query:QueryParameter,func:Function = null):void{
			var stmt:SQLStatement = new SQLStatement();
			stmt.sqlConnection = this._conn;
			
			var where:String = this._get_where(stmt,query);
			
			var sql:String = "DELETE FROM " + this.tableName + where;
			
			stmt.text = sql;
			
			this.lastSql = sql;
			var _deleteWhereFunc:Function = function():void{
				var result:SQLResult = stmt.getResult();
				if(func != null){
					func(result);
				}
				fireDeleteEvent(result);
				stmt.removeEventListener(SQLEvent.RESULT,_deleteWhereFunc);
			};
			stmt.addEventListener(SQLEvent.RESULT,_deleteWhereFunc);
			stmt.execute();
			
			
		}
		
		
		
		/*
		public function execDelete(where:String):void{
			if(where == null || where.length < 1 ){
				throw new IllegalOperationError("where is NULL");
			}
			var stmt:SQLStatement = new SQLStatement();
			stmt.sqlConnection = this._conn;
			stmt.addEventListener(SQLEvent.RESULT,fireDeleteEvent);
			var sql:String = "DELETE FROM " + this.tableName + " WHERE " + where;
			stmt.text = sql;
			lastSql = sql;
			stmt.execute();
		}
		*/
		
		
		public function fireDeleteEvent(result:SQLResult):void{
			
			var ne:TableEvent = new TableEvent(TableEvent.DELETE);
			ne.result = result;
			ne.tableObject = this;
			dispatchEvent(ne);
			
			var ch:TableEvent = new TableEvent(TableEvent.CHANGE_TOTAL);
			ch.result = result;
			ch.tableObject = this;
			dispatchEvent(ch);
			
			var chg:TableEvent = new TableEvent(TableEvent.TABLE_CHANGE);
			chg.result = result;
			chg.tableObject = this;
			dispatchEvent(chg);
			
			if(debug)_log.debug("dispatchUpdateEvent - " + result.rowsAffected);
		}
		
		
		public function getRowFuture(query:QueryParameter):IResultFuture{
			var stmt:SQLStatement = new SQLStatement();
			stmt.sqlConnection = _conn;
			
			var sql:String = "SELECT * FROM " + this.tableName + this._get_where(stmt,query);
			
			if(query.order){
				sql += " ORDER BY " + query.order;
			}
			this.lastSql = sql;
			stmt.text = sql;
			
			if(this.itemClass){
				stmt.itemClass = this.itemClass;
			}
			
			var future:IResultFuture = new ResultFuture(stmt);
			return future;
		}
		
		/**
		 *  1レコードだけ取得する。
		 * 
		 *  resultFunc で登録した関数の中で、 handleGetRowを呼べば簡単にオブジェクトが取得できます。
		 */
		/*
		public function getRow(where:Object,resultFunc:Function,errorFunc:Function = null,clz:Class = null):SQLStatement{
			var stmt:SQLStatement = new SQLStatement();
			stmt.sqlConnection = _conn;
			var ret:Boolean = false;
			
			stmt.addEventListener(SQLEvent.RESULT,resultFunc);
			if(errorFunc != null){
				stmt.addEventListener(SQLErrorEvent.ERROR,errorFunc);
			}
			
			var sql:String = "SELECT * FROM " + this.tableName;
			if(where != null){
				
				if(where is String){
					sql = sql + " WHERE " + where;
				}
				else{
				
				if(where.text != null){
					sql = sql + " WHERE " + where.text;
				}
				if(where.args != null ){
					if(where.args is String){
						stmt.parameters[1] = where.args;
					}
					else if(where.args is Number){
						stmt.parameters[1] = where.args;
					}
					else if(where.args is Array){
						var arr:Array = where.args;
						for(var key:String in arr){
							_log.debug("where args : " + key);
						}
					}
				}
				}
			}
			
			if(clz != null){
				stmt.itemClass = clz;
			}
			
			sql = sql + " LIMIT 1 ";
			stmt.text = sql;
			if($__debug__)_log.debug("SQL " + sql);
			stmt.execute();
			return stmt;
		}
		*/
		
		/**
		 *  1レコードだけ取得する。
		 * 
		 *  resultFunc で登録した関数の中で、 handleGetRowを呼べば簡単にオブジェクトが取得できます。
		 */
		public function getListFuture(query:QueryParameter = null):IResultFuture{
			var stmt:SQLStatement = new SQLStatement();
			stmt.sqlConnection = _conn;
			
			var sql:String = "SELECT * FROM " + this.tableName; 
			
			if(query){
				sql += this._get_where(stmt,query);
			
				if(query.order){
					sql += " ORDER BY " + query.order;
				}
			
				if(query.limit > -1 ){
					sql = sql + " LIMIT " + query.limit;
				}
				if(query.offset > -1){
					sql = sql + " OFFSET " + query.offset;
				}
			}
			this.lastSql = sql;
			stmt.text = sql;
			
			if(this.itemClass){
				stmt.itemClass = this.itemClass;
			}
			
			var future:IResultFuture = new ResultFuture(stmt);
			return future;
		}
		
		
		/**
		 * 
		 * getRow メソッド結果を簡単に取得するメソッド。
		 * SQLEvent.RESULTのイベント処理の中で呼ぶ。
		 *
		 * 
		 */
		/*
		public function getRowResult(result:SQLResult):Object{
			if(result != null && result.data != null){
				if(result.data.length > 0 ){
					return result.data[0];
				}
				else{
					return null;
				}
			}
			else{
				return null;
			}
		}
		*/
		
		
		
		
		/**
		 *  シンプルなSQLとDB接続を設定した上でSQLStatmentを返す。
		 *  
		 */  
		public function getStatement(where:String = null,order:String = null):IResultFuture{
			var stmt:SQLStatement = new SQLStatement();
			stmt.sqlConnection = _conn;
			var sql:String = "SELECT * FROM " + this.tableName;
			if(where != null){
				sql = sql + " WHERE " + where;
			}
			if(order != null){
				sql += " ORDER BY " + order;
			}
			stmt.text = sql;
			var future:ResultFuture = new ResultFuture(stmt);
			return future;
		}
		
		/**
		 * テーブルのサイズを返す
		 */
		public function getTotal(where:String = null):IResultFuture{
			var stmt:SQLStatement = new SQLStatement();
			stmt.sqlConnection = _conn;
			var sql:String = "SELECT count(*) FROM " + this.tableName;
			if(where != null){
				sql = sql + " WHERE " + where;
			}
			stmt.text = sql;
			var future:ResultFuture = new ResultFuture(stmt);
			return future;
		}
		
		public function getTotalFuture(query:QueryParameter = null):IResultFuture{
			var stmt:SQLStatement = new SQLStatement();
			stmt.sqlConnection = _conn;
			
			var sql:String = "SELECT count(*) FROM " + this.tableName; 
			
			if(query){
				sql += this._get_where(stmt,query);
			}
			this.lastSql = sql;
			stmt.text = sql;
			
			var future:IResultFuture = new ResultFuture(stmt);
			return future;
		}
		
		public function createSimpleStatement(sql:String):SQLStatement{
			var stmt:SQLStatement = new SQLStatement();
			stmt.sqlConnection = _conn;
			stmt.text = sql;
			return stmt;
		}
		
		public function createQueryStatement(stringOrQueryParameter:Object,clz:Class = null):SQLStatement{
			var stmt:SQLStatement = new SQLStatement();
			stmt.sqlConnection = _conn;
			var ret:Boolean = false;
			var field:String = "*";
			
			
			var sql:String = "";
			if(stringOrQueryParameter != null){	
				if(stringOrQueryParameter is String){
					sql = "SELECT * FROM " + this.tableName + " WHERE " + stringOrQueryParameter;
				}
				else{
					var params:QueryParameter = stringOrQueryParameter as QueryParameter;
					if(params){
						if(params.where != null){
							sql = sql + "WHERE " + params.where;
						}
						if(params.args != null ){
							if(params.args is Array){
								if($__debug__) _log.debug("args is Array ");
								var arr:Array = params.args as Array;
								for(var i:int=0; i<arr.length; i++){
									stmt.parameters[i] = params.args[i];
								}
							}
							else if(params.args is String){
								stmt.parameters[0] = params.args;
							}
							else if(params.args is Number){
								stmt.parameters[0] = params.args;
							}
							else if(params.args is Object){
								if($__debug__) _log.debug("args is Object");
								for(var key:String in params.args){
									stmt.parameters[":" + key] = params.args[key];
								}
							}
							else{
								stmt.parameters[0] = params.args;
							}
						}
						
						
						if(params.limit > -1 ){
							sql = sql + " LIMIT " + params.limit;
						}
						if(params.offset > -1){
							sql = sql + " OFFSET " + params.offset;
						}
						
						sql = "SELECT " + params.fields + " FROM " + this.tableName + " " + sql;
					}
				}
			}
			if(sql == null || sql.length < 1){
				sql = "SELECT * FROM " + this.tableName;
			}
			
			if(clz != null){
				stmt.itemClass = clz;
			}
			stmt.text = sql;
			if(debug)_log.debug("[SQL] " + sql);
			return stmt;
		}
		
		/**
		 * すべての結果を取得する
		 */
		/*
		public function getAll(itemClass:Class = null,func:Function = null):SQLStatement{
			var stmt:SQLStatement = createQueryStatement(null,itemClass);
			var allFunc:Function = function():void{
				var result:SQLResult = stmt.getResult();
				if(func != null){
					func(result);
				}
				stmt.removeEventListener(SQLEvent.RESULT,allFunc);
			};
			stmt.addEventListener(SQLEvent.RESULT,allFunc);
			stmt.execute();
			return stmt;
		}
		*/
		/*
		public function getList(opts:Object,itemClass:Class = null,func:Function = null):void{
			var stmt:SQLStatement = this.createQueryStatement(opts,itemClass);
			
			var selectFunc:Function = function():void{
				var result:SQLResult = stmt.getResult();
				stmt.removeEventListener(SQLEvent.RESULT,selectFunc);
				func(result);
			};
			stmt.addEventListener(SQLEvent.RESULT,selectFunc);
			stmt.execute();	
		}
		*/
		
		/*
		public function handleGetMap(event:SQLEvent,key:String):Object{
			var stmt:SQLStatement = event.target as SQLStatement;
			var result:SQLResult = stmt.getResult();
			if( result != null && result.data != null ){
				var retObj:Object = new Object();
				_log.debug("getMap : found (" + result.data.length + ")");
				var size:int = result.data.length;
				for(var i:int =0 ; i < size; i++){
					var dat:Object = result.data[i];
					if(dat[key] != null){
						var kStr:String = dat[key];
						retObj[kStr] = dat;
					}
				}
				return retObj;
			}
			return null;
		}
		*/
		/**
		*  登録に成功した場合に、最後に登録されたIDを取得する
		*
		*/
		/*
		public function handleLastInsertId(event:SQLEvent):Number{
			var stmt:SQLStatement = event.target as SQLStatement;
			var result:SQLResult = stmt.getResult();
			if(result == null){
				return -1;	
			}
			return result.lastInsertRowID;
		}
		*/
		/**
		 * シーケンス番号を取得する
		 * 
		 */
		/*
		public function nextval(seqName:String):Number{
			var stmt:SQLStatement = new SQLStatement();
			stmt.sqlConnection = this._conn;
			stmt.text = "INSERT INTO seq_" + this.tableName + "_" + seqName + " VALUES(NULL)";
			try{
				stmt.execute();
				return stmt.getResult().lastInsertRowID;
			}
			catch(e:SQLError){
				
			}
			return -1;
		}
		*/
		
		private function getFieldType(type:String):int{
			type = type.toUpperCase();
			switch(type){
				case "INTEGER":
				case "INT":
				case "BOOLEAN":
				case "BOOL":
					return 	FIELD_INTEGER;
				case "TEXT":
				case "CHAR":
				case "VARCHAR":
					return FIELD_TEXT;
				case "TIMESTAMP":
				case "DATE":
					return FIELD_DATE;
			}
			return -1;
		}
		
		public function debugTrace():void{
			_log.debug("*****  DEBUG TRACE ******");
			_log.debug(" table name : " + this.tableName );
			
		}
		
		private function _get_where(stmt:SQLStatement,query:QueryParameter):String{
			var where_array:Array = new Array();
			if(query){
				if(query.systemWhere){
					where_array.push("(" + query.systemWhere + ")");
				}
				if(query.where){
					where_array.push(query.where);
				}
				
				if(query.args){
					if(ObjectUtil.isDynamicObject(query.args)){
						for(var key:String in query.args){
							stmt.parameters[":" + key] = query.args[key];
						}
					}
					else{
						if(query.args is Array){
							var arr:Array = query.args as Array;
							for(var s:int = 0; s < arr.length; s++){
								stmt.parameters[s] = arr[s];
							}
							
						}
						else{
							stmt.parameters[0] = query.args;
						}
					}
				}
			}
			
			if(where_array.length > 0){
				return " WHERE " + where_array.join(" AND ");
			}
			return "";
		}
	}
}
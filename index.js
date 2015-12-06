/*** HomelyAlarm Z-Way HA module *******************************************

Version: 1.0.0
(c) Maroš Kollár, 2015
-----------------------------------------------------------------------------
Author: Maroš Kollár <maros@k-1.com>
Description:
    This module allows to send alarm notifications via HomelyAlarm
    server https://github.com/maros/HomelyAlarm

******************************************************************************/

function HomelyAlarm (id, controller) {
    // Call superconstructor first (AutomationModule)
    HomelyAlarm.super_.call(this, id, controller);
    
    this.eventHandlers = {};
}

inherits(HomelyAlarm, AutomationModule);

_module = HomelyAlarm;

// ----------------------------------------------------------------------------
// --- Module instance initialized
// ----------------------------------------------------------------------------

HomelyAlarm.prototype.init = function (config) {
    HomelyAlarm.super_.prototype.init.call(this, config);
    
    var self = this;
    
    self.eventHandlers = {};
    _.each(self.config.events,function(element,index) {
        _.each(self.listenEvents,function(handlerName,event){
            var handler = _.bind(self[handlerName],self,element);
            self.controller.on(element.type+'.'+event,handler);
            self.eventHandlers[index+event] = handler;
        });
    });
    
    executeFile("modules/HomelyAlarm/sha1.js");
};

HomelyAlarm.prototype.stop = function () {
    var self = this;
    
    _.each(self.config.events,function(element,index) {
        _.each(self.listenEvents,function(event,handlerName){
            self.controller.odd(element.type+'.'+event,self.eventHandlers[index+event]);
        });
    });
    self.eventHandlers = {};
    
    HomelyAlarm.super_.prototype.stop.call(this);
};

// ----------------------------------------------------------------------------
// --- Module methods
// ----------------------------------------------------------------------------

HomelyAlarm.prototype.listenEvents = {
    "alarm":            "handleAlarm",
    "stop":             "handleStop",
    "delayed_alarm":    "handleDelayedAlarm",
    "delayed_cancel":   "handleDelayedCancel",
    "warning":          "handleWarning"
};

HomelyAlarm.prototype.severityActions = [
    "email",
    "sms",
    "voice"
];

HomelyAlarm.prototype.handleEvent = function (eventConfig,event) {
    var self = this;
    
    /* warning,error,info,notification */
    
    // SecurityZone.warning
    // Rain.warning
    //
    
    /*
            id: Math.floor(now.getTime() /1000),
            timestamp: now.toISOString(),
            level: severity,
            message: message, 
            type: type || 'device',
            source: source,
            redeemed: false,
            // add unified hash - produces with source, cause timestamp in sec is not unique ...
            h: this.hashCode(source)
     */
    self.remoteCall('event');

//local url           = ALARM.SERVER.."/alarm/"..action.."?"
//    
//    if params == nil then
//        params = {}
//    end
//    params["time"]      = os.time()
//    params["status"]    = luup.variable_get(SID.SELF,"Status", SELF)
//    
//    for key,value in pairs(params) do
//        url = url.."&"..key.."="..string.url_encode(value)
//    end
//    local signature     = hmac_sha1(ALARM.SECRET,url)
//    local respbody      = {}
//    
//    luup.log("[MyHome] Calling remote alarm "..action..":"..url..":"..signature)
//    local result, code, headers = HTTP.request{
//        url     = url,
//        method  = "POST",
//        headers = {
//            ["X-HomelyAlarm-Signature"] = signature
//        },
//        sink    = ltn12.sink.table(respbody)
//    }
//    
//    if code ~= 200 then
//        respbody = table.concat(respbody)
//        luup.log("[MyHome] Failed remote alarm with status "..code.." (".. respbody.." "..url..")",1)
//    end
//    
};

HomelyAlarm.prototype.remoteCall = function(action,params) {
    var self = this;
    
    executeFile("modules/HomelyAlarm/sha1.js");
    
    // Build query_string
    params = params || {};
    params.time = (new Date()).getTime();
    var queryString = _.reduce(
        params,
        function ( components, value, key ) {
          components.push( key + '=' + encodeURIComponent( value ) );
          return components;
        },
        []
    ).join( '&' );
    
    // Build URL
    var url = this.server;
    if (!url.match(/\/$/)) {
        url = url + '/';
    }
    url = url + action;
    
    // Build signature
    var sha = new jsSHA(url, "TEXT");
    var signature = sha.getHMAC(this.secret, "TEXT", "SHA-512", "HEX");
    
    // HTTP request
    http.request({
        method: 'POST',
        url: url,
        data: queryString,
        headers: {
            "X-HomelyAlarm-Signature": signature
        },
        async: true,
        success: function(response) {},
        error: function(response) {}
    });
};
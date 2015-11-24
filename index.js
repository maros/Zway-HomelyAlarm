/*** NotificationHomelyAlarm Z-Way HA module *******************************************

Version: 1.0.0
(c) Maroš Kollár, 2015
-----------------------------------------------------------------------------
Author: Maroš Kollár <maros@k-1.com>
Description:
    This module allows to send alarm notifications via NotificationHomelyAlarm
    server https://github.com/maros/NotificationHomelyAlarm

******************************************************************************/

function NotificationHomelyAlarm (id, controller) {
    // Call superconstructor first (AutomationModule)
    NotificationHomelyAlarm.super_.call(this, id, controller);
}

inherits(NotificationHomelyAlarm, AutomationModule);

_module = NotificationHomelyAlarm;

// ----------------------------------------------------------------------------
// --- Module instance initialized
// ----------------------------------------------------------------------------

NotificationHomelyAlarm.prototype.init = function (config) {
    NotificationHomelyAlarm.super_.prototype.init.call(this, config);
    
    var self = this;
    
    this.handler = _bind(self.onNotificationHandler,self);
    
    this.controller.on('notifications.push', this.handler);
    
    _.each('')
};

NotificationHomelyAlarm.prototype.stop = function () {
    NotificationHomelyAlarm.super_.prototype.stop.call(this);

    this.controller.off('notifications.push', this.handler);
};

// ----------------------------------------------------------------------------
// --- Module methods
// ----------------------------------------------------------------------------

NotificationHomelyAlarm.prototype.events = [
    "alarm", "delayed_alarm", "cancel", "warning"
];

NotificationHomelyAlarm.prototype.types = [
    "intrusion", "flood", "smoke", "gas", "heat", "cold", "tamper", "other", "rain"
];

NotificationHomelyAlarm.prototype.allEvents = function() {
    var self = this;
    
    _.each(self.events,function() {
        
    });
};

NotificationHomelyAlarm.prototype.onNotificationHandler = function (notification) {
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
//            ["X-NotificationHomelyAlarm-Signature"] = signature
//        },
//        sink    = ltn12.sink.table(respbody)
//    }
//    
//    if code ~= 200 then
//        respbody = table.concat(respbody)
//        luup.log("[MyHome] Failed remote alarm with status "..code.." (".. respbody.." "..url..")",1)
//    end
//    
}

NotificationHomelyAlarm.prototype.remoteCall = function(action,params) {
    var self = this;
    
    executeFile(config.libPath + "/sha.js");
    
    // Build query_string
    params = params || {};
    params.time = (new Date).getTime();
    var query_string = _.reduce(
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
        data: query_string,
        headers: {
            "X-NotificationHomelyAlarm-Signature": signature
        },
        async: true,
        success: function(response) {},
        error: function(response) {}
    });
}
 
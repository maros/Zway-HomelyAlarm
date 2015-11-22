/*** NotificationHomelyAlarm Z-Way HA module *******************************************

Version: 1.0.0
(c) Maroš Kollár, 2015
-----------------------------------------------------------------------------
Author: Maroš Kollár <maros@k-1.com>
Description:
    This module allows to send notifications via NotificationHomelyAlarm server
    https://github.com/maros/NotificationHomelyAlarm

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

    this.handler = this.onNotificationHandler();
    
    this.secret = config.secret.toString();
    this.server = config.server.toString();

    this.controller.on('notifications.push', this.handler);
};

NotificationHomelyAlarm.prototype.stop = function () {
    NotificationSMSru.super_.prototype.stop.call(this);

    this.controller.off('notifications.push', this.handler);
};

// ----------------------------------------------------------------------------
// --- Module methods
// ----------------------------------------------------------------------------

NotificationHomelyAlarm.prototype.onNotificationHandler = function () {
    var self = this;
    
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
    
    return function(notice) {
        http.request({
            method: 'POST',
            url: th,
            data: {
                api_id: self.api_key,
                to: self.phone,
                text: self.prefix + " " + notice.message
            }
        });
    }
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
 
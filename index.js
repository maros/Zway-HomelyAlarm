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
            var type = element.type;
            if (type === 'other') {
                type = 'security.' + element.otherType;
            }
            self.controller.on(type+'.'+event,handler);
            self.eventHandlers[index+event] = handler;
        });
    });
    
    executeFile(self.moduleBasePath()+"/sha1.js");
};

HomelyAlarm.prototype.stop = function () {
    var self = this;

    _.each(self.config.events,function(element,index) {
        _.each(self.listenEvents,function(handlerName,event){
            var type = element.type;
            if (type === 'other') {
                type = 'security.' + element.otherType;
            }
            self.controller.off(type+'.'+event,self.eventHandlers[index+event]);
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
    "delayAlarm":       "handleDelayAlarm",
    "delayCancel":      "handleDelayCancel",
    "warning":          "handleWarning"
};

HomelyAlarm.prototype.severityActions = {
    "pushbullet": 1,
    "email": 1,
    "sms": 2,
    "call": 3
};

HomelyAlarm.prototype.handleAlarm = function (eventConfig,event) {
    var self = this;

    console.log('[HomelyAlarm] Got '+eventConfig.type+' alarm event (severity '+eventConfig.severity+')');
    self.handleEvent('start',event,self.getRecipients(eventConfig.severity));
};

HomelyAlarm.prototype.handleStop = function (eventConfig,event) {
    var self = this;

    console.log('[HomelyAlarm] Got '+eventConfig.type+' stop event (severity '+eventConfig.severity+')');
    //self.handleEvent('stop',event);
};

HomelyAlarm.prototype.handleDelayAlarm = function (eventConfig,event) {
    var self = this;

    console.log('[HomelyAlarm] Got '+eventConfig.type+' delayAlarm event (severity '+eventConfig.severity+')');
    self.handleEvent('delayed',event,self.getRecipients(eventConfig.severity));
};

HomelyAlarm.prototype.handleDelayCancel = function (eventConfig,event) {
    var self = this;

    console.log('[HomelyAlarm] Got '+eventConfig.type+' delayCancel event (severity '+eventConfig.severity+')');
    self.handleEvent('cancel',event);
};

HomelyAlarm.prototype.handleWarning = function (eventConfig,event) {
    var self = this;

    console.log('[HomelyAlarm] Got '+eventConfig.type+' warning event');
    self.handleEvent('warning',event,self.getRecipients(1));
};

HomelyAlarm.prototype.handleEvent = function(action,event,recipients) {
    var self = this;

    var params = {
        id: event.id,
        language: self.controller.defaultLang
    };
    _.each(['message','title','type','delay'],function(key) {
        if (typeof(event[key]) !== 'undefined') {
            params[key] = event[key];
        }
    });

    if (typeof(recipients) !== 'undefined') {
        params.recipients = recipients;
    }
    self.remoteCall(action,params);
};

HomelyAlarm.prototype.getRecipients = function(eventSeverity) {
    var self = this;

    eventSeverity = parseInt(eventSeverity);

    var recipients = [];
    _.each(self.config.recipients,function(element) {
        var recipientSeverity = parseInt(element.severity);
        if (recipientSeverity > eventSeverity) {
            return;
        }

        var recipient = { severity: eventSeverity };
        if (element.telephone) {
            if (element.call) {
                recipient.call = element.telephone;
            }
            if (element.sms) {
                recipient.sms = element.telephone;
            }
        }
        if (element.pushbullet) {
            recipient.pushbullet = element.pushbullet;
        }
        if (element.email) {
            recipient.email = element.email;
        }

        // Find prefered communication method
        var findSeverity = function(index,severity,action) {
            if (typeof(recipient.prefered) === 'undefined'
                && typeof(recipient[action]) !== 'undefined'
                && severity == index) {
                recipient.prefered = action;
            }
        };

        console.logJS(self.severityActions);
        for(var s = eventSeverity; s >= 1; s--) {
            _.each(self.severityActions,_.bind(findSeverity,self,s));
        }

        for(var i = eventSeverity; i <= 3; i++) {
            _.each(self.severityActions,_.bind(findSeverity,self,i));
        }

        recipients.push(recipient);
    });

    console.logJS(recipients);
    return recipients;
};

HomelyAlarm.prototype.remoteCall = function(action,params) {
    var self = this;

    // Build query_string
    params = params || {};
    params.time = (new Date()).getTime();

    var queryString = JSON.stringify(params);

    // Build URL
    var url = self.config.server;
    if (!url.match(/\/$/)) {
        url = url + '/';
    }
    url = url + 'alarm/' + action;

    console.log('[HomelyAlarm] Remote request to '+url+' with '+queryString);

    // Build signature
    var sha = new jsSHA("SHA-1", "TEXT");
    sha.setHMACKey(self.config.secret, "TEXT");
    sha.update(queryString);
    var signature = sha.getHMAC("HEX");
    
    // HTTP request
    http.request({
        method: 'POST',
        url: url,
        data: queryString,
        contentType: "application/json",
        headers: {
            "Content-Type": "application/json",
            "X-HomelyAlarm-Signature": signature
        },
        async: true,
        success: function(response) {},
        error: function(response) {
            console.error('[HomelyAlarm] Could not call alarm server: '+response.status );
        }
    });
};
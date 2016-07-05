# Zway-HomelyAlarm

Send tamper proof notifications originating from various sources such as 
security zones (Security Zone automation module) and rain detectors 
(see Virtual Rain Sensor) to selected recipients. Notifications can be sent 
using multiple methods.

* Voice calls via twilio.com (with fall back to other transportation means when recipient does not pick up the phone)
* SMS via twilio.com (with fall back to other transportation means if SMS cannot be delivered)
* e-Mail
* Pushbullet notifications

This module consists of two parts, a zway automation module, and
a server that needs to be deployed on a separate, publicly reachable, server.

The server works closely with the SecurityZone module and ensures proper
security even in case of tampering. In case of an delayed alarm (eg. 
intrusion) the communication between the SecurityZone module and HomelyAlarm
works as follows

1. SecurityZone detects an open door and sends a delayed alarm event
2. HomelyAlarm modules notifies the HomelyAlarm server
3. If the SecurityZone module gets disarmed during the delay period the
alarm on the server will be cancelled too.
4. If tampering of the zway server occurs in the meantime (eg. by turning 
off the electricity), and the server does not receive the alarm cancellation
event, the notifications will be sent after the selected delay period.

# Configuration

## server

URL of the HomelyAlarm server

## secret

Shared secret of the HomelyAlarm server

## recipients

List of recipients

## recipients.severity

Contact this recipient when event severity is greater than or equal to the
event severity level.

## recipients.telephone, recipients.email

Telephone number and e-mail address.

## recipients.call, recipients.sms

Selects if recipient telephone number should be used for calls, SMS or both

## events

List of events that should be handled

## events.type

Type of event to trigger notification.

## events.severity

Assign a severity level to this event type.

# Events

The module listens to the configured events.

No events are emitted.

# Virtual Devices

No virtual device is created

# Alarm Server

TODO

# Installation

The prefered way of installing this module is via the "Zwave.me App Store"
available in 2.2.0 and higher. For stable module releases no access token is 
required. If you want to test the latest pre-releases use 'k1_beta' as 
app store access token.

For developers and users of older Zway versions installation via git is 
recommended.

```shell
cd /opt/z-way-server/automation/userModules
git clone https://github.com/maros/Zway-HomelyAlarm.git HomelyAlarm --branch latest
```

To update or install a specific version
```shell
cd /opt/z-way-server/automation/userModules/HomelyAlarm
git fetch --tags
# For latest released version
git checkout tags/latest
# For a specific version
git checkout tags/1.02
# For development version
git checkout -b master --track origin/master
```

Alternatively this module can be installed via the Z-Wave.me app store. Just
go to Management > App Store Access and add 'k1_beta' access token.

Then you need to install the alarm server on a second host that can be
reached publicly.

Just checkout this repository as stated above on the machine that will run
the server. The server code is located in the server subdirectory. 

TODO

# License

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or any 
later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

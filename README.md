# Zway-HomelyAlarm

Send notifications originating from various sources, such as security zones to alert
selected recipients. This module consists of two parts, a zway automation module, and
a server that needs to be deployed on a separate, publicly reachable, server.

# Configuration

## server

URL of the HomelyAlarm server

## secret

Shared secret of the HomelyAlarm server

## recipients

List of recipients

## recipients.severity

Contact this recipient when event severity is greater than or equal to the event
severity level.

## recipients.telephone, recipients.email

Telephone number and e-mail address.

## recipients.call, recipients.sms

Selects if recipient telephone number should be used for calls, SMS or both

## events

List of events that should be handled

## events.type

Type of event to trigger notification.

## events.severity

Severity level associated with the event

# Events

The module listens to the configured events.

No events are emitted.

# Virtual Devices

No virtual device is created

# Alarm Server

TODO

# Installation

First install the module on the zway host.

```shell
cd /opt/z-way-server/automation/modules
git clone https://github.com/maros/Zway-HomelyAlarm.git HomelyAlarm --branch latest
```

To update or install a specific version
```shell
cd /opt/z-way-server/automation/modules/HomelyAlarm
git fetch --tags
# For latest released version
git checkout tags/latest
# For a specific version
git checkout tags/1.02
# For development version
git checkout -b master --track origin/master
```

Then you need to install the alarm server on a second host that can be
reached publicly.

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

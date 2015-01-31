# CHANGELOG

## 1.5.1
  Now for redic

## 1.5.0

* Subscribe +switch-master again
* Prevents master discovery to get stuck in endless loop if sentinels
  are not available
* Always reconnect at least once, even if reconnect timeout is 0
* Catch networking errors which bubble up past redis

## 1.4.4

* Allow client to return list of slaves
* Fix compatibility issues with ruby 1.8.7

## 1.4.3

* Fix for pipelined requests and readonly calls

## 1.4.2

* Fix sentinel reconnection broken

## 1.4.1

* Fix only one sentinel client reconnect issue

## 1.4.0

* Rewrite sentinel client to follow http://redis.io/topics/sentinel
* Parse uri string in sentinels array

## 1.3.0

* Add ability to reconnect all redis sentinel clients
* Avoid the config gets modified
* Reconnect if redis suddenly becones read-only

## 1.2.0

* Add redis synchrony support
* Add redis authentication support

## 1.1.4

* Fix discover_master procedure wich failover_reconnect_wait option
* Add test_wait_for_failover_write example

## 1.1.3

* Cache sentinel connections
* Add option failover_reconnect_timeout
* Add option failover_reconnect_wait
* Add test_wait_for_failover example

## 1.1.2

* Ruby 1.8.7 compatibility

## 1.1.1

* Fix initialize Redis::ConnectionError

## 1.1.0

* Remove background thread, which subscribes switch-master message
* Add example

## 1.0.0

* First version

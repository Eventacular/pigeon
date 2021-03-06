[![Build Status](https://travis-ci.org/codedge-llc/pigeon.svg?branch=master)](https://travis-ci.org/codedge-llc/pigeon)
[![Hex.pm](http://img.shields.io/hexpm/v/pigeon.svg)](https://hex.pm/packages/pigeon) [![Hex.pm](http://img.shields.io/hexpm/dt/pigeon.svg)](https://hex.pm/packages/pigeon)
# Pigeon
HTTP2-compliant wrapper for sending iOS and Android push notifications.

## Installation
Add pigeon as a `mix.exs` dependency:

**Note: Pigeon's API will likely change until v1.0**
  ```elixir
  def deps do
    [{:pigeon, "~> 0.5.0"}]
  end
  ```
  
After running `mix deps.get`, configure `mix.exs` to start the application automatically.
  ```elixir
  def application do
    [applications: [:pigeon]]
  end
  ```
  
## GCM (Android)
### Usage
1. Set your environment variables.
  ```elixir
  config :pigeon, 
    gcm_key: "your_gcm_key_here"
  ```
  
2. Create a notification packet. 
  ```elixir
  data = %{ message: "your message" }
  n = Pigeon.GCM.Notification.new(data, "your device registration ID")
  ```
 
3. Send the packet.
  ```elixir
  Pigeon.GCM.push(n)
  ```
  
### Sending to Multiple Registration IDs
Pass in a list of registration IDs, as many as you want. IDs will automatically be chunked into sets of 1000 before sending the push (as per GCM guidelines).
  ```elixir
  data = %{ message: "your message" }
  n = Pigeon.GCM.Notification.new(data, ["first ID", "second ID"])
  ```


### Notification Struct
When using `Pigeon.GCM.Notification.new/2`, `message_id` and `updated_registration` will always be `nil`. These keys are set in the response callback. `registration_id` can either be a single string or a list of strings.
```elixir
%Pigeon.GCM.Notification{
    data: nil,
    message_id: nil,
    registration_id: nil,
    updated_registration_id: nil
}
```

## APNS (Apple iOS)
### Usage
1. Set your environment variables. See below for setting up your certificate and key.
  ```elixir
  config :pigeon, 
    apns_mode: :dev,
    apns_cert: "cert.pem",
    apns_key: "key_unencrypted.pem"
  ```

2. Create a notification packet. **Note: Your push topic is generally the app's bundle identifier.**
  ```elixir
  n = Pigeon.APNS.Notification.new("your message", "your device token", "your push topic")
  ```
  
  
3. Send the packet.
  ```elixir
  Pigeon.APNS.push(n)
  ```
  
### Generating Your Certificate and Key .pem
1. In Keychain Access, right-click your push certificate and select _"Export..."_
2. Export the certificate as `cert.p12`
3. Click the dropdown arrow next to the certificate, right-click the private key and select _"Export..."_
4. Export the private key as `key.p12`
5. From a shell, convert the certificate.
   ```
   openssl pkcs12 -clcerts -nokeys -out cert.pem -in cert.p12
   ```
   
6. Convert the key.
   ```
   openssl pkcs12 -nocerts -out key.pem -in key.p12
   ```

7. Remove the password from the key.
   ```
   openssl rsa -in key.pem -out key_unencrypted.pem
   ```
   
8. `cert.pem` and `key_unencrypted.pem` can now be used as the cert and key in `Pigeon.push`, respectively. Set them in your `config.exs`

### Notifications with Custom Data
Notifications can contain additional information for the `aps` key with a map passed as an optional 4th parameter (e.g. setting badge counters or defining custom sounds)
  ```elixir
  n = Pigeon.APNS.Notification.new("your message", "your device token", "your push topic", %{
    badge: 5,
    sound: "default"
  })
  ```
  
Or define custom payload data with an optional 5th parameter:
  ```elixir
  n = Pigeon.APNS.Notification.new("your message", "your device token", "your push topic", %{}, %{
    your-custom-key: %{
      custom-value: 500
    }
  })
  ```

## Handling Push Responses
### GCM
1. Pass an optional anonymous function as your second parameter. This function will get called on each registration ID assuming some of them were successful.
  ```elixir
  data = %{ message: "your message" }
  n = Pigeon.GCM.Notification.new(data, "device registration ID")
  Pigeon.GCM.push(n, fn(x) -> IO.inspect(x) end)
  ```
  
2. Reponses return a tuple of either `{:ok, notification}` or `{:error, reason, notification}`. You could handle responses like so:
  ```elixir
  on_response = fn(x) ->
    case x do
      {:ok, notification} ->
        # Push successful, check to see if the registration ID changed
        if !is_nil(notification.updated_registration_id) do
          # Update the registration ID in the database
        end
      {:error, :InvalidRegistration, notification} ->
        # Remove the bad ID from the database
      {:error, reason, notification} ->
        # Handle other errors
    end
  end
  
  data = %{ message: "your message" }
  n = Pigeon.GCM.Notification.new(data, "your device token")
  Pigeon.GCM.push(n, on_response)
  ```
  
Notification structs returned as `{:ok, notification}` will always contain exactly one registration ID for the `registration_id` key. 

For `{:error, reason, notification}` tuples, this key can be one or many IDs depending on the error. `:InvalidRegistration` will return exactly one, whereas `:AuthenticationError` and `:InternalServerError` will return up to 1000 IDs (and the callback called for each failed 1000-chunked request).
  
#### Error Responses
*Slightly modified from [GCM Server Reference](https://developers.google.com/cloud-messaging/http-server-ref#error-codes)*

|Reason                     |Description                  |
|---------------------------|-----------------------------|
|:MissingRegistration       |Missing Registration Token   |
|:InvalidRegistration       |Invalid Registration Token   |
|:NotRegistered             |Unregistered Device          |
|:InvalidPackageName        |Invalid Package Name         |
|:AuthenticationError       |Authentication Error         |
|:MismatchSenderId          |Mismatched Sender            |
|:InvalidJSON               |Invalid JSON                 |
|:MessageTooBig             |Message Too Big              |
|:InvalidDataKey            |Invalid Data Key             |
|:InvalidTtl                |Invalid Time to Live         |
|:Unavailable               |Timeout                      |
|:InternalServerError       |Internal Server Error        |
|:DeviceMessageRateExceeded |Message Rate Exceeded        |
|:TopicsMessageRateExceeded |Topics Message Rate Exceeded |
|:UnknownError              |Unknown Error                |

### APNS
1. Pass an optional anonymous function as your second parameter.
  ```elixir
  n = Pigeon.APNS.Notification.new("your message", "your device token", "your push topic")
  Pigeon.APNS.push(n, fn(x) -> IO.inspect(x) end)
  ```

2. Responses return a tuple of either `{:ok, notification}` or `{:error, reason, notification}`. You could handle responses like so:
  ```elixir
  on_response = fn(x) ->
    case x do
      {:ok, notification} ->
        Logger.debug "Push successful!"
      {:error, :BadDeviceToken, notification} ->
        Logger.error "Bad device token!"
      {:error, reason, notification} ->
        Logger.error "Some other error happened."
    end
  end

  n = Pigeon.APNS.Notification.new("your message", "your device token", "your push topic")
  Pigeon.APNS.push(n, on_response)
  ```

#### Error Responses
*Taken from [APNS Provider API](https://developer.apple.com/library/ios/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/Chapters/APNsProviderAPI.html#//apple_ref/doc/uid/TP40008194-CH101-SW3)*

|Reason                     |Description                   |
|---------------------------|------------------------------|
|:PayloadEmpty              |The message payload was empty.|
|:PayloadTooLarge           |The message payload was too large. The maximum payload size is 4096 bytes.|
|:BadTopic                  |The apns-topic was invalid.|
|:TopicDisallowed           |Pushing to this topic is not allowed.|
|:BadMessageId              |The apns-id value is bad.|
|:BadExpirationDate         |The apns-expiration value is bad.|
|:BadPriority               |The apns-priority value is bad.|
|:MissingDeviceToken        |The device token is not specified in the request :path. Verify that the :path header contains the device token.|
|:BadDeviceToken            |The specified device token was bad. Verify that the request contains a valid token and that the token matches the environment.|
|:DeviceTokenNotForTopic    |The device token does not match the specified topic.|
|:Unregistered              |The device token is inactive for the specified topic.|
|:DuplicateHeaders          |One or more headers were repeated.|
|:BadCertificateEnvironment |The client certificate was for the wrong environment.|
|:BadCertificate            |The certificate was bad.|
|:Forbidden                 |The specified action is not allowed.|
|:BadPath                   |The request contained a bad :path value.|
|:MethodNotAllowed          |The specified :method was not POST.|
|:TooManyRequests           |Too many requests were made consecutively to the same device token.|
|:IdleTimeout               |Idle time out.|
|:Shutdown                  |The server is shutting down.|
|:InternalServerError       |An internal server error occurred.|
|:ServiceUnavailable        |The service is unavailable.|
|:MissingTopic              |The apns-topic header of the request was not specified and was required. The apns-topic header is mandatory when the client is connected using a certificate that supports multiple topics.|

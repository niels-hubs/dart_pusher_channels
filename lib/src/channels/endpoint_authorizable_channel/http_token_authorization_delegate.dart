import 'dart:async';
import 'dart:convert';
import 'package:dart_pusher_channels/src/channels/private_channel.dart';
import 'package:dart_pusher_channels/src/exceptions/exception.dart';
import 'package:http/http.dart' as http;
import 'package:dart_pusher_channels/src/channels/endpoint_authorizable_channel/endpoint_authorization_delegate.dart';
import 'package:meta/meta.dart';

typedef EndpointAuthorizableChannelTokenAuthorizationParser<
        T extends EndpointAuthorizationData>
    = FutureOr<T> Function(http.Response response);

class EndpointAuthorizableChannelTokenAuthorizationException
    implements PusherChannelsException {
  final http.Response response;
  final Uri authorizationEndpoint;

  const EndpointAuthorizableChannelTokenAuthorizationException._({
    required this.response,
    required this.authorizationEndpoint,
  });

  @override
  String get message =>
      'Failed to get authorization data. Response to $authorizationEndpoint was:\n $response';
}

@immutable
class EndpointAuthorizableChannelTokenAuthorizationDelegate<
        T extends EndpointAuthorizationData>
    implements EndpointAuthorizableChannelAuthorizationDelegate<T> {
  final Uri authorizationEndpoint;
  final Map<String, String> headers;
  @protected
  final EndpointAuthorizableChannelTokenAuthorizationParser<T> parser;

  const EndpointAuthorizableChannelTokenAuthorizationDelegate._({
    required this.authorizationEndpoint,
    required this.headers,
    required this.parser,
  });

  @override
  Future<T> authorizationData(String socketId, String channelName) async {
    final response = await http.post(
      authorizationEndpoint,
      headers: {
        ...headers,
        'content-type': 'application/x-www-form-urlencoded'
      },
      body: {
        'socket_id': socketId,
        'channel_name': channelName,
      },
    );

    if (response.statusCode != 200) {
      throw EndpointAuthorizableChannelTokenAuthorizationException._(
        response: response,
        authorizationEndpoint: authorizationEndpoint,
      );
    }
    return parser(response);
  }

  static EndpointAuthorizableChannelTokenAuthorizationDelegate<
      PrivateChannelAuthorizationData> forPrivateChannel({
    required Uri authorizationEndpoint,
    required Map<String, String> headers,
    EndpointAuthorizableChannelTokenAuthorizationParser<
            PrivateChannelAuthorizationData>
        parser = defaultParserForPrivateChannel,
  }) =>
      EndpointAuthorizableChannelTokenAuthorizationDelegate._(
        authorizationEndpoint: authorizationEndpoint,
        headers: headers,
        parser: parser,
      );

  static PrivateChannelAuthorizationData defaultParserForPrivateChannel(
    http.Response response,
  ) {
    final decoded = jsonDecode(response.body) as Map;
    final auth = decoded['auth'] as String;

    return PrivateChannelAuthorizationData(
      authKey: auth,
    );
  }
}
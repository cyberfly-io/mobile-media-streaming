// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'flutter_api.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$FlutterStreamEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlutterStreamEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'FlutterStreamEvent()';
}


}

/// @nodoc
class $FlutterStreamEventCopyWith<$Res>  {
$FlutterStreamEventCopyWith(FlutterStreamEvent _, $Res Function(FlutterStreamEvent) __);
}


/// Adds pattern-matching-related methods to [FlutterStreamEvent].
extension FlutterStreamEventPatterns on FlutterStreamEvent {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( FlutterStreamEvent_NeighborUp value)?  neighborUp,TResult Function( FlutterStreamEvent_NeighborDown value)?  neighborDown,TResult Function( FlutterStreamEvent_Presence value)?  presence,TResult Function( FlutterStreamEvent_MediaChunk value)?  mediaChunk,TResult Function( FlutterStreamEvent_Signal value)?  signal,TResult Function( FlutterStreamEvent_Lagged value)?  lagged,TResult Function( FlutterStreamEvent_Error value)?  error,required TResult orElse(),}){
final _that = this;
switch (_that) {
case FlutterStreamEvent_NeighborUp() when neighborUp != null:
return neighborUp(_that);case FlutterStreamEvent_NeighborDown() when neighborDown != null:
return neighborDown(_that);case FlutterStreamEvent_Presence() when presence != null:
return presence(_that);case FlutterStreamEvent_MediaChunk() when mediaChunk != null:
return mediaChunk(_that);case FlutterStreamEvent_Signal() when signal != null:
return signal(_that);case FlutterStreamEvent_Lagged() when lagged != null:
return lagged(_that);case FlutterStreamEvent_Error() when error != null:
return error(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( FlutterStreamEvent_NeighborUp value)  neighborUp,required TResult Function( FlutterStreamEvent_NeighborDown value)  neighborDown,required TResult Function( FlutterStreamEvent_Presence value)  presence,required TResult Function( FlutterStreamEvent_MediaChunk value)  mediaChunk,required TResult Function( FlutterStreamEvent_Signal value)  signal,required TResult Function( FlutterStreamEvent_Lagged value)  lagged,required TResult Function( FlutterStreamEvent_Error value)  error,}){
final _that = this;
switch (_that) {
case FlutterStreamEvent_NeighborUp():
return neighborUp(_that);case FlutterStreamEvent_NeighborDown():
return neighborDown(_that);case FlutterStreamEvent_Presence():
return presence(_that);case FlutterStreamEvent_MediaChunk():
return mediaChunk(_that);case FlutterStreamEvent_Signal():
return signal(_that);case FlutterStreamEvent_Lagged():
return lagged(_that);case FlutterStreamEvent_Error():
return error(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( FlutterStreamEvent_NeighborUp value)?  neighborUp,TResult? Function( FlutterStreamEvent_NeighborDown value)?  neighborDown,TResult? Function( FlutterStreamEvent_Presence value)?  presence,TResult? Function( FlutterStreamEvent_MediaChunk value)?  mediaChunk,TResult? Function( FlutterStreamEvent_Signal value)?  signal,TResult? Function( FlutterStreamEvent_Lagged value)?  lagged,TResult? Function( FlutterStreamEvent_Error value)?  error,}){
final _that = this;
switch (_that) {
case FlutterStreamEvent_NeighborUp() when neighborUp != null:
return neighborUp(_that);case FlutterStreamEvent_NeighborDown() when neighborDown != null:
return neighborDown(_that);case FlutterStreamEvent_Presence() when presence != null:
return presence(_that);case FlutterStreamEvent_MediaChunk() when mediaChunk != null:
return mediaChunk(_that);case FlutterStreamEvent_Signal() when signal != null:
return signal(_that);case FlutterStreamEvent_Lagged() when lagged != null:
return lagged(_that);case FlutterStreamEvent_Error() when error != null:
return error(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String endpointId)?  neighborUp,TResult Function( String endpointId)?  neighborDown,TResult Function( String from,  String name,  BigInt timestamp)?  presence,TResult Function( String from,  Uint8List data,  BigInt sequence,  BigInt timestamp)?  mediaChunk,TResult Function( String from,  Uint8List data,  BigInt timestamp)?  signal,TResult Function()?  lagged,TResult Function( String message)?  error,required TResult orElse(),}) {final _that = this;
switch (_that) {
case FlutterStreamEvent_NeighborUp() when neighborUp != null:
return neighborUp(_that.endpointId);case FlutterStreamEvent_NeighborDown() when neighborDown != null:
return neighborDown(_that.endpointId);case FlutterStreamEvent_Presence() when presence != null:
return presence(_that.from,_that.name,_that.timestamp);case FlutterStreamEvent_MediaChunk() when mediaChunk != null:
return mediaChunk(_that.from,_that.data,_that.sequence,_that.timestamp);case FlutterStreamEvent_Signal() when signal != null:
return signal(_that.from,_that.data,_that.timestamp);case FlutterStreamEvent_Lagged() when lagged != null:
return lagged();case FlutterStreamEvent_Error() when error != null:
return error(_that.message);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String endpointId)  neighborUp,required TResult Function( String endpointId)  neighborDown,required TResult Function( String from,  String name,  BigInt timestamp)  presence,required TResult Function( String from,  Uint8List data,  BigInt sequence,  BigInt timestamp)  mediaChunk,required TResult Function( String from,  Uint8List data,  BigInt timestamp)  signal,required TResult Function()  lagged,required TResult Function( String message)  error,}) {final _that = this;
switch (_that) {
case FlutterStreamEvent_NeighborUp():
return neighborUp(_that.endpointId);case FlutterStreamEvent_NeighborDown():
return neighborDown(_that.endpointId);case FlutterStreamEvent_Presence():
return presence(_that.from,_that.name,_that.timestamp);case FlutterStreamEvent_MediaChunk():
return mediaChunk(_that.from,_that.data,_that.sequence,_that.timestamp);case FlutterStreamEvent_Signal():
return signal(_that.from,_that.data,_that.timestamp);case FlutterStreamEvent_Lagged():
return lagged();case FlutterStreamEvent_Error():
return error(_that.message);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String endpointId)?  neighborUp,TResult? Function( String endpointId)?  neighborDown,TResult? Function( String from,  String name,  BigInt timestamp)?  presence,TResult? Function( String from,  Uint8List data,  BigInt sequence,  BigInt timestamp)?  mediaChunk,TResult? Function( String from,  Uint8List data,  BigInt timestamp)?  signal,TResult? Function()?  lagged,TResult? Function( String message)?  error,}) {final _that = this;
switch (_that) {
case FlutterStreamEvent_NeighborUp() when neighborUp != null:
return neighborUp(_that.endpointId);case FlutterStreamEvent_NeighborDown() when neighborDown != null:
return neighborDown(_that.endpointId);case FlutterStreamEvent_Presence() when presence != null:
return presence(_that.from,_that.name,_that.timestamp);case FlutterStreamEvent_MediaChunk() when mediaChunk != null:
return mediaChunk(_that.from,_that.data,_that.sequence,_that.timestamp);case FlutterStreamEvent_Signal() when signal != null:
return signal(_that.from,_that.data,_that.timestamp);case FlutterStreamEvent_Lagged() when lagged != null:
return lagged();case FlutterStreamEvent_Error() when error != null:
return error(_that.message);case _:
  return null;

}
}

}

/// @nodoc


class FlutterStreamEvent_NeighborUp extends FlutterStreamEvent {
  const FlutterStreamEvent_NeighborUp({required this.endpointId}): super._();
  

 final  String endpointId;

/// Create a copy of FlutterStreamEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FlutterStreamEvent_NeighborUpCopyWith<FlutterStreamEvent_NeighborUp> get copyWith => _$FlutterStreamEvent_NeighborUpCopyWithImpl<FlutterStreamEvent_NeighborUp>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlutterStreamEvent_NeighborUp&&(identical(other.endpointId, endpointId) || other.endpointId == endpointId));
}


@override
int get hashCode => Object.hash(runtimeType,endpointId);

@override
String toString() {
  return 'FlutterStreamEvent.neighborUp(endpointId: $endpointId)';
}


}

/// @nodoc
abstract mixin class $FlutterStreamEvent_NeighborUpCopyWith<$Res> implements $FlutterStreamEventCopyWith<$Res> {
  factory $FlutterStreamEvent_NeighborUpCopyWith(FlutterStreamEvent_NeighborUp value, $Res Function(FlutterStreamEvent_NeighborUp) _then) = _$FlutterStreamEvent_NeighborUpCopyWithImpl;
@useResult
$Res call({
 String endpointId
});




}
/// @nodoc
class _$FlutterStreamEvent_NeighborUpCopyWithImpl<$Res>
    implements $FlutterStreamEvent_NeighborUpCopyWith<$Res> {
  _$FlutterStreamEvent_NeighborUpCopyWithImpl(this._self, this._then);

  final FlutterStreamEvent_NeighborUp _self;
  final $Res Function(FlutterStreamEvent_NeighborUp) _then;

/// Create a copy of FlutterStreamEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? endpointId = null,}) {
  return _then(FlutterStreamEvent_NeighborUp(
endpointId: null == endpointId ? _self.endpointId : endpointId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class FlutterStreamEvent_NeighborDown extends FlutterStreamEvent {
  const FlutterStreamEvent_NeighborDown({required this.endpointId}): super._();
  

 final  String endpointId;

/// Create a copy of FlutterStreamEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FlutterStreamEvent_NeighborDownCopyWith<FlutterStreamEvent_NeighborDown> get copyWith => _$FlutterStreamEvent_NeighborDownCopyWithImpl<FlutterStreamEvent_NeighborDown>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlutterStreamEvent_NeighborDown&&(identical(other.endpointId, endpointId) || other.endpointId == endpointId));
}


@override
int get hashCode => Object.hash(runtimeType,endpointId);

@override
String toString() {
  return 'FlutterStreamEvent.neighborDown(endpointId: $endpointId)';
}


}

/// @nodoc
abstract mixin class $FlutterStreamEvent_NeighborDownCopyWith<$Res> implements $FlutterStreamEventCopyWith<$Res> {
  factory $FlutterStreamEvent_NeighborDownCopyWith(FlutterStreamEvent_NeighborDown value, $Res Function(FlutterStreamEvent_NeighborDown) _then) = _$FlutterStreamEvent_NeighborDownCopyWithImpl;
@useResult
$Res call({
 String endpointId
});




}
/// @nodoc
class _$FlutterStreamEvent_NeighborDownCopyWithImpl<$Res>
    implements $FlutterStreamEvent_NeighborDownCopyWith<$Res> {
  _$FlutterStreamEvent_NeighborDownCopyWithImpl(this._self, this._then);

  final FlutterStreamEvent_NeighborDown _self;
  final $Res Function(FlutterStreamEvent_NeighborDown) _then;

/// Create a copy of FlutterStreamEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? endpointId = null,}) {
  return _then(FlutterStreamEvent_NeighborDown(
endpointId: null == endpointId ? _self.endpointId : endpointId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class FlutterStreamEvent_Presence extends FlutterStreamEvent {
  const FlutterStreamEvent_Presence({required this.from, required this.name, required this.timestamp}): super._();
  

 final  String from;
 final  String name;
 final  BigInt timestamp;

/// Create a copy of FlutterStreamEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FlutterStreamEvent_PresenceCopyWith<FlutterStreamEvent_Presence> get copyWith => _$FlutterStreamEvent_PresenceCopyWithImpl<FlutterStreamEvent_Presence>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlutterStreamEvent_Presence&&(identical(other.from, from) || other.from == from)&&(identical(other.name, name) || other.name == name)&&(identical(other.timestamp, timestamp) || other.timestamp == timestamp));
}


@override
int get hashCode => Object.hash(runtimeType,from,name,timestamp);

@override
String toString() {
  return 'FlutterStreamEvent.presence(from: $from, name: $name, timestamp: $timestamp)';
}


}

/// @nodoc
abstract mixin class $FlutterStreamEvent_PresenceCopyWith<$Res> implements $FlutterStreamEventCopyWith<$Res> {
  factory $FlutterStreamEvent_PresenceCopyWith(FlutterStreamEvent_Presence value, $Res Function(FlutterStreamEvent_Presence) _then) = _$FlutterStreamEvent_PresenceCopyWithImpl;
@useResult
$Res call({
 String from, String name, BigInt timestamp
});




}
/// @nodoc
class _$FlutterStreamEvent_PresenceCopyWithImpl<$Res>
    implements $FlutterStreamEvent_PresenceCopyWith<$Res> {
  _$FlutterStreamEvent_PresenceCopyWithImpl(this._self, this._then);

  final FlutterStreamEvent_Presence _self;
  final $Res Function(FlutterStreamEvent_Presence) _then;

/// Create a copy of FlutterStreamEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? from = null,Object? name = null,Object? timestamp = null,}) {
  return _then(FlutterStreamEvent_Presence(
from: null == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,timestamp: null == timestamp ? _self.timestamp : timestamp // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class FlutterStreamEvent_MediaChunk extends FlutterStreamEvent {
  const FlutterStreamEvent_MediaChunk({required this.from, required this.data, required this.sequence, required this.timestamp}): super._();
  

 final  String from;
 final  Uint8List data;
 final  BigInt sequence;
 final  BigInt timestamp;

/// Create a copy of FlutterStreamEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FlutterStreamEvent_MediaChunkCopyWith<FlutterStreamEvent_MediaChunk> get copyWith => _$FlutterStreamEvent_MediaChunkCopyWithImpl<FlutterStreamEvent_MediaChunk>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlutterStreamEvent_MediaChunk&&(identical(other.from, from) || other.from == from)&&const DeepCollectionEquality().equals(other.data, data)&&(identical(other.sequence, sequence) || other.sequence == sequence)&&(identical(other.timestamp, timestamp) || other.timestamp == timestamp));
}


@override
int get hashCode => Object.hash(runtimeType,from,const DeepCollectionEquality().hash(data),sequence,timestamp);

@override
String toString() {
  return 'FlutterStreamEvent.mediaChunk(from: $from, data: $data, sequence: $sequence, timestamp: $timestamp)';
}


}

/// @nodoc
abstract mixin class $FlutterStreamEvent_MediaChunkCopyWith<$Res> implements $FlutterStreamEventCopyWith<$Res> {
  factory $FlutterStreamEvent_MediaChunkCopyWith(FlutterStreamEvent_MediaChunk value, $Res Function(FlutterStreamEvent_MediaChunk) _then) = _$FlutterStreamEvent_MediaChunkCopyWithImpl;
@useResult
$Res call({
 String from, Uint8List data, BigInt sequence, BigInt timestamp
});




}
/// @nodoc
class _$FlutterStreamEvent_MediaChunkCopyWithImpl<$Res>
    implements $FlutterStreamEvent_MediaChunkCopyWith<$Res> {
  _$FlutterStreamEvent_MediaChunkCopyWithImpl(this._self, this._then);

  final FlutterStreamEvent_MediaChunk _self;
  final $Res Function(FlutterStreamEvent_MediaChunk) _then;

/// Create a copy of FlutterStreamEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? from = null,Object? data = null,Object? sequence = null,Object? timestamp = null,}) {
  return _then(FlutterStreamEvent_MediaChunk(
from: null == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as String,data: null == data ? _self.data : data // ignore: cast_nullable_to_non_nullable
as Uint8List,sequence: null == sequence ? _self.sequence : sequence // ignore: cast_nullable_to_non_nullable
as BigInt,timestamp: null == timestamp ? _self.timestamp : timestamp // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class FlutterStreamEvent_Signal extends FlutterStreamEvent {
  const FlutterStreamEvent_Signal({required this.from, required this.data, required this.timestamp}): super._();
  

 final  String from;
 final  Uint8List data;
 final  BigInt timestamp;

/// Create a copy of FlutterStreamEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FlutterStreamEvent_SignalCopyWith<FlutterStreamEvent_Signal> get copyWith => _$FlutterStreamEvent_SignalCopyWithImpl<FlutterStreamEvent_Signal>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlutterStreamEvent_Signal&&(identical(other.from, from) || other.from == from)&&const DeepCollectionEquality().equals(other.data, data)&&(identical(other.timestamp, timestamp) || other.timestamp == timestamp));
}


@override
int get hashCode => Object.hash(runtimeType,from,const DeepCollectionEquality().hash(data),timestamp);

@override
String toString() {
  return 'FlutterStreamEvent.signal(from: $from, data: $data, timestamp: $timestamp)';
}


}

/// @nodoc
abstract mixin class $FlutterStreamEvent_SignalCopyWith<$Res> implements $FlutterStreamEventCopyWith<$Res> {
  factory $FlutterStreamEvent_SignalCopyWith(FlutterStreamEvent_Signal value, $Res Function(FlutterStreamEvent_Signal) _then) = _$FlutterStreamEvent_SignalCopyWithImpl;
@useResult
$Res call({
 String from, Uint8List data, BigInt timestamp
});




}
/// @nodoc
class _$FlutterStreamEvent_SignalCopyWithImpl<$Res>
    implements $FlutterStreamEvent_SignalCopyWith<$Res> {
  _$FlutterStreamEvent_SignalCopyWithImpl(this._self, this._then);

  final FlutterStreamEvent_Signal _self;
  final $Res Function(FlutterStreamEvent_Signal) _then;

/// Create a copy of FlutterStreamEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? from = null,Object? data = null,Object? timestamp = null,}) {
  return _then(FlutterStreamEvent_Signal(
from: null == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as String,data: null == data ? _self.data : data // ignore: cast_nullable_to_non_nullable
as Uint8List,timestamp: null == timestamp ? _self.timestamp : timestamp // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class FlutterStreamEvent_Lagged extends FlutterStreamEvent {
  const FlutterStreamEvent_Lagged(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlutterStreamEvent_Lagged);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'FlutterStreamEvent.lagged()';
}


}




/// @nodoc


class FlutterStreamEvent_Error extends FlutterStreamEvent {
  const FlutterStreamEvent_Error({required this.message}): super._();
  

 final  String message;

/// Create a copy of FlutterStreamEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FlutterStreamEvent_ErrorCopyWith<FlutterStreamEvent_Error> get copyWith => _$FlutterStreamEvent_ErrorCopyWithImpl<FlutterStreamEvent_Error>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlutterStreamEvent_Error&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,message);

@override
String toString() {
  return 'FlutterStreamEvent.error(message: $message)';
}


}

/// @nodoc
abstract mixin class $FlutterStreamEvent_ErrorCopyWith<$Res> implements $FlutterStreamEventCopyWith<$Res> {
  factory $FlutterStreamEvent_ErrorCopyWith(FlutterStreamEvent_Error value, $Res Function(FlutterStreamEvent_Error) _then) = _$FlutterStreamEvent_ErrorCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$FlutterStreamEvent_ErrorCopyWithImpl<$Res>
    implements $FlutterStreamEvent_ErrorCopyWith<$Res> {
  _$FlutterStreamEvent_ErrorCopyWithImpl(this._self, this._then);

  final FlutterStreamEvent_Error _self;
  final $Res Function(FlutterStreamEvent_Error) _then;

/// Create a copy of FlutterStreamEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(FlutterStreamEvent_Error(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on

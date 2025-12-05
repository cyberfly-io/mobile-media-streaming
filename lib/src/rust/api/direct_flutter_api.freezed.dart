// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'direct_flutter_api.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$FlutterDirectEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlutterDirectEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'FlutterDirectEvent()';
}


}

/// @nodoc
class $FlutterDirectEventCopyWith<$Res>  {
$FlutterDirectEventCopyWith(FlutterDirectEvent _, $Res Function(FlutterDirectEvent) __);
}


/// Adds pattern-matching-related methods to [FlutterDirectEvent].
extension FlutterDirectEventPatterns on FlutterDirectEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( FlutterDirectEvent_PeerConnected value)?  peerConnected,TResult Function( FlutterDirectEvent_PeerDisconnected value)?  peerDisconnected,TResult Function( FlutterDirectEvent_RequestMetadata value)?  requestMetadata,TResult Function( FlutterDirectEvent_Metadata value)?  metadata,TResult Function( FlutterDirectEvent_RequestChunk value)?  requestChunk,TResult Function( FlutterDirectEvent_Chunk value)?  chunk,TResult Function( FlutterDirectEvent_Presence value)?  presence,TResult Function( FlutterDirectEvent_Signal value)?  signal,TResult Function( FlutterDirectEvent_Error value)?  error,required TResult orElse(),}){
final _that = this;
switch (_that) {
case FlutterDirectEvent_PeerConnected() when peerConnected != null:
return peerConnected(_that);case FlutterDirectEvent_PeerDisconnected() when peerDisconnected != null:
return peerDisconnected(_that);case FlutterDirectEvent_RequestMetadata() when requestMetadata != null:
return requestMetadata(_that);case FlutterDirectEvent_Metadata() when metadata != null:
return metadata(_that);case FlutterDirectEvent_RequestChunk() when requestChunk != null:
return requestChunk(_that);case FlutterDirectEvent_Chunk() when chunk != null:
return chunk(_that);case FlutterDirectEvent_Presence() when presence != null:
return presence(_that);case FlutterDirectEvent_Signal() when signal != null:
return signal(_that);case FlutterDirectEvent_Error() when error != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( FlutterDirectEvent_PeerConnected value)  peerConnected,required TResult Function( FlutterDirectEvent_PeerDisconnected value)  peerDisconnected,required TResult Function( FlutterDirectEvent_RequestMetadata value)  requestMetadata,required TResult Function( FlutterDirectEvent_Metadata value)  metadata,required TResult Function( FlutterDirectEvent_RequestChunk value)  requestChunk,required TResult Function( FlutterDirectEvent_Chunk value)  chunk,required TResult Function( FlutterDirectEvent_Presence value)  presence,required TResult Function( FlutterDirectEvent_Signal value)  signal,required TResult Function( FlutterDirectEvent_Error value)  error,}){
final _that = this;
switch (_that) {
case FlutterDirectEvent_PeerConnected():
return peerConnected(_that);case FlutterDirectEvent_PeerDisconnected():
return peerDisconnected(_that);case FlutterDirectEvent_RequestMetadata():
return requestMetadata(_that);case FlutterDirectEvent_Metadata():
return metadata(_that);case FlutterDirectEvent_RequestChunk():
return requestChunk(_that);case FlutterDirectEvent_Chunk():
return chunk(_that);case FlutterDirectEvent_Presence():
return presence(_that);case FlutterDirectEvent_Signal():
return signal(_that);case FlutterDirectEvent_Error():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( FlutterDirectEvent_PeerConnected value)?  peerConnected,TResult? Function( FlutterDirectEvent_PeerDisconnected value)?  peerDisconnected,TResult? Function( FlutterDirectEvent_RequestMetadata value)?  requestMetadata,TResult? Function( FlutterDirectEvent_Metadata value)?  metadata,TResult? Function( FlutterDirectEvent_RequestChunk value)?  requestChunk,TResult? Function( FlutterDirectEvent_Chunk value)?  chunk,TResult? Function( FlutterDirectEvent_Presence value)?  presence,TResult? Function( FlutterDirectEvent_Signal value)?  signal,TResult? Function( FlutterDirectEvent_Error value)?  error,}){
final _that = this;
switch (_that) {
case FlutterDirectEvent_PeerConnected() when peerConnected != null:
return peerConnected(_that);case FlutterDirectEvent_PeerDisconnected() when peerDisconnected != null:
return peerDisconnected(_that);case FlutterDirectEvent_RequestMetadata() when requestMetadata != null:
return requestMetadata(_that);case FlutterDirectEvent_Metadata() when metadata != null:
return metadata(_that);case FlutterDirectEvent_RequestChunk() when requestChunk != null:
return requestChunk(_that);case FlutterDirectEvent_Chunk() when chunk != null:
return chunk(_that);case FlutterDirectEvent_Presence() when presence != null:
return presence(_that);case FlutterDirectEvent_Signal() when signal != null:
return signal(_that);case FlutterDirectEvent_Error() when error != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String endpointId)?  peerConnected,TResult Function( String endpointId)?  peerDisconnected,TResult Function( String from,  BigInt timestamp)?  requestMetadata,TResult Function( String from,  String fileName,  BigInt fileSize,  String mimeType,  int totalChunks,  double? duration,  BigInt timestamp)?  metadata,TResult Function( String from,  int index,  BigInt timestamp)?  requestChunk,TResult Function( String from,  int index,  Uint8List data,  BigInt timestamp)?  chunk,TResult Function( String from,  String name,  BigInt timestamp)?  presence,TResult Function( String from,  Uint8List data,  BigInt timestamp)?  signal,TResult Function( String message)?  error,required TResult orElse(),}) {final _that = this;
switch (_that) {
case FlutterDirectEvent_PeerConnected() when peerConnected != null:
return peerConnected(_that.endpointId);case FlutterDirectEvent_PeerDisconnected() when peerDisconnected != null:
return peerDisconnected(_that.endpointId);case FlutterDirectEvent_RequestMetadata() when requestMetadata != null:
return requestMetadata(_that.from,_that.timestamp);case FlutterDirectEvent_Metadata() when metadata != null:
return metadata(_that.from,_that.fileName,_that.fileSize,_that.mimeType,_that.totalChunks,_that.duration,_that.timestamp);case FlutterDirectEvent_RequestChunk() when requestChunk != null:
return requestChunk(_that.from,_that.index,_that.timestamp);case FlutterDirectEvent_Chunk() when chunk != null:
return chunk(_that.from,_that.index,_that.data,_that.timestamp);case FlutterDirectEvent_Presence() when presence != null:
return presence(_that.from,_that.name,_that.timestamp);case FlutterDirectEvent_Signal() when signal != null:
return signal(_that.from,_that.data,_that.timestamp);case FlutterDirectEvent_Error() when error != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String endpointId)  peerConnected,required TResult Function( String endpointId)  peerDisconnected,required TResult Function( String from,  BigInt timestamp)  requestMetadata,required TResult Function( String from,  String fileName,  BigInt fileSize,  String mimeType,  int totalChunks,  double? duration,  BigInt timestamp)  metadata,required TResult Function( String from,  int index,  BigInt timestamp)  requestChunk,required TResult Function( String from,  int index,  Uint8List data,  BigInt timestamp)  chunk,required TResult Function( String from,  String name,  BigInt timestamp)  presence,required TResult Function( String from,  Uint8List data,  BigInt timestamp)  signal,required TResult Function( String message)  error,}) {final _that = this;
switch (_that) {
case FlutterDirectEvent_PeerConnected():
return peerConnected(_that.endpointId);case FlutterDirectEvent_PeerDisconnected():
return peerDisconnected(_that.endpointId);case FlutterDirectEvent_RequestMetadata():
return requestMetadata(_that.from,_that.timestamp);case FlutterDirectEvent_Metadata():
return metadata(_that.from,_that.fileName,_that.fileSize,_that.mimeType,_that.totalChunks,_that.duration,_that.timestamp);case FlutterDirectEvent_RequestChunk():
return requestChunk(_that.from,_that.index,_that.timestamp);case FlutterDirectEvent_Chunk():
return chunk(_that.from,_that.index,_that.data,_that.timestamp);case FlutterDirectEvent_Presence():
return presence(_that.from,_that.name,_that.timestamp);case FlutterDirectEvent_Signal():
return signal(_that.from,_that.data,_that.timestamp);case FlutterDirectEvent_Error():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String endpointId)?  peerConnected,TResult? Function( String endpointId)?  peerDisconnected,TResult? Function( String from,  BigInt timestamp)?  requestMetadata,TResult? Function( String from,  String fileName,  BigInt fileSize,  String mimeType,  int totalChunks,  double? duration,  BigInt timestamp)?  metadata,TResult? Function( String from,  int index,  BigInt timestamp)?  requestChunk,TResult? Function( String from,  int index,  Uint8List data,  BigInt timestamp)?  chunk,TResult? Function( String from,  String name,  BigInt timestamp)?  presence,TResult? Function( String from,  Uint8List data,  BigInt timestamp)?  signal,TResult? Function( String message)?  error,}) {final _that = this;
switch (_that) {
case FlutterDirectEvent_PeerConnected() when peerConnected != null:
return peerConnected(_that.endpointId);case FlutterDirectEvent_PeerDisconnected() when peerDisconnected != null:
return peerDisconnected(_that.endpointId);case FlutterDirectEvent_RequestMetadata() when requestMetadata != null:
return requestMetadata(_that.from,_that.timestamp);case FlutterDirectEvent_Metadata() when metadata != null:
return metadata(_that.from,_that.fileName,_that.fileSize,_that.mimeType,_that.totalChunks,_that.duration,_that.timestamp);case FlutterDirectEvent_RequestChunk() when requestChunk != null:
return requestChunk(_that.from,_that.index,_that.timestamp);case FlutterDirectEvent_Chunk() when chunk != null:
return chunk(_that.from,_that.index,_that.data,_that.timestamp);case FlutterDirectEvent_Presence() when presence != null:
return presence(_that.from,_that.name,_that.timestamp);case FlutterDirectEvent_Signal() when signal != null:
return signal(_that.from,_that.data,_that.timestamp);case FlutterDirectEvent_Error() when error != null:
return error(_that.message);case _:
  return null;

}
}

}

/// @nodoc


class FlutterDirectEvent_PeerConnected extends FlutterDirectEvent {
  const FlutterDirectEvent_PeerConnected({required this.endpointId}): super._();
  

 final  String endpointId;

/// Create a copy of FlutterDirectEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FlutterDirectEvent_PeerConnectedCopyWith<FlutterDirectEvent_PeerConnected> get copyWith => _$FlutterDirectEvent_PeerConnectedCopyWithImpl<FlutterDirectEvent_PeerConnected>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlutterDirectEvent_PeerConnected&&(identical(other.endpointId, endpointId) || other.endpointId == endpointId));
}


@override
int get hashCode => Object.hash(runtimeType,endpointId);

@override
String toString() {
  return 'FlutterDirectEvent.peerConnected(endpointId: $endpointId)';
}


}

/// @nodoc
abstract mixin class $FlutterDirectEvent_PeerConnectedCopyWith<$Res> implements $FlutterDirectEventCopyWith<$Res> {
  factory $FlutterDirectEvent_PeerConnectedCopyWith(FlutterDirectEvent_PeerConnected value, $Res Function(FlutterDirectEvent_PeerConnected) _then) = _$FlutterDirectEvent_PeerConnectedCopyWithImpl;
@useResult
$Res call({
 String endpointId
});




}
/// @nodoc
class _$FlutterDirectEvent_PeerConnectedCopyWithImpl<$Res>
    implements $FlutterDirectEvent_PeerConnectedCopyWith<$Res> {
  _$FlutterDirectEvent_PeerConnectedCopyWithImpl(this._self, this._then);

  final FlutterDirectEvent_PeerConnected _self;
  final $Res Function(FlutterDirectEvent_PeerConnected) _then;

/// Create a copy of FlutterDirectEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? endpointId = null,}) {
  return _then(FlutterDirectEvent_PeerConnected(
endpointId: null == endpointId ? _self.endpointId : endpointId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class FlutterDirectEvent_PeerDisconnected extends FlutterDirectEvent {
  const FlutterDirectEvent_PeerDisconnected({required this.endpointId}): super._();
  

 final  String endpointId;

/// Create a copy of FlutterDirectEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FlutterDirectEvent_PeerDisconnectedCopyWith<FlutterDirectEvent_PeerDisconnected> get copyWith => _$FlutterDirectEvent_PeerDisconnectedCopyWithImpl<FlutterDirectEvent_PeerDisconnected>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlutterDirectEvent_PeerDisconnected&&(identical(other.endpointId, endpointId) || other.endpointId == endpointId));
}


@override
int get hashCode => Object.hash(runtimeType,endpointId);

@override
String toString() {
  return 'FlutterDirectEvent.peerDisconnected(endpointId: $endpointId)';
}


}

/// @nodoc
abstract mixin class $FlutterDirectEvent_PeerDisconnectedCopyWith<$Res> implements $FlutterDirectEventCopyWith<$Res> {
  factory $FlutterDirectEvent_PeerDisconnectedCopyWith(FlutterDirectEvent_PeerDisconnected value, $Res Function(FlutterDirectEvent_PeerDisconnected) _then) = _$FlutterDirectEvent_PeerDisconnectedCopyWithImpl;
@useResult
$Res call({
 String endpointId
});




}
/// @nodoc
class _$FlutterDirectEvent_PeerDisconnectedCopyWithImpl<$Res>
    implements $FlutterDirectEvent_PeerDisconnectedCopyWith<$Res> {
  _$FlutterDirectEvent_PeerDisconnectedCopyWithImpl(this._self, this._then);

  final FlutterDirectEvent_PeerDisconnected _self;
  final $Res Function(FlutterDirectEvent_PeerDisconnected) _then;

/// Create a copy of FlutterDirectEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? endpointId = null,}) {
  return _then(FlutterDirectEvent_PeerDisconnected(
endpointId: null == endpointId ? _self.endpointId : endpointId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class FlutterDirectEvent_RequestMetadata extends FlutterDirectEvent {
  const FlutterDirectEvent_RequestMetadata({required this.from, required this.timestamp}): super._();
  

 final  String from;
 final  BigInt timestamp;

/// Create a copy of FlutterDirectEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FlutterDirectEvent_RequestMetadataCopyWith<FlutterDirectEvent_RequestMetadata> get copyWith => _$FlutterDirectEvent_RequestMetadataCopyWithImpl<FlutterDirectEvent_RequestMetadata>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlutterDirectEvent_RequestMetadata&&(identical(other.from, from) || other.from == from)&&(identical(other.timestamp, timestamp) || other.timestamp == timestamp));
}


@override
int get hashCode => Object.hash(runtimeType,from,timestamp);

@override
String toString() {
  return 'FlutterDirectEvent.requestMetadata(from: $from, timestamp: $timestamp)';
}


}

/// @nodoc
abstract mixin class $FlutterDirectEvent_RequestMetadataCopyWith<$Res> implements $FlutterDirectEventCopyWith<$Res> {
  factory $FlutterDirectEvent_RequestMetadataCopyWith(FlutterDirectEvent_RequestMetadata value, $Res Function(FlutterDirectEvent_RequestMetadata) _then) = _$FlutterDirectEvent_RequestMetadataCopyWithImpl;
@useResult
$Res call({
 String from, BigInt timestamp
});




}
/// @nodoc
class _$FlutterDirectEvent_RequestMetadataCopyWithImpl<$Res>
    implements $FlutterDirectEvent_RequestMetadataCopyWith<$Res> {
  _$FlutterDirectEvent_RequestMetadataCopyWithImpl(this._self, this._then);

  final FlutterDirectEvent_RequestMetadata _self;
  final $Res Function(FlutterDirectEvent_RequestMetadata) _then;

/// Create a copy of FlutterDirectEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? from = null,Object? timestamp = null,}) {
  return _then(FlutterDirectEvent_RequestMetadata(
from: null == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as String,timestamp: null == timestamp ? _self.timestamp : timestamp // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class FlutterDirectEvent_Metadata extends FlutterDirectEvent {
  const FlutterDirectEvent_Metadata({required this.from, required this.fileName, required this.fileSize, required this.mimeType, required this.totalChunks, this.duration, required this.timestamp}): super._();
  

 final  String from;
 final  String fileName;
 final  BigInt fileSize;
 final  String mimeType;
 final  int totalChunks;
 final  double? duration;
 final  BigInt timestamp;

/// Create a copy of FlutterDirectEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FlutterDirectEvent_MetadataCopyWith<FlutterDirectEvent_Metadata> get copyWith => _$FlutterDirectEvent_MetadataCopyWithImpl<FlutterDirectEvent_Metadata>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlutterDirectEvent_Metadata&&(identical(other.from, from) || other.from == from)&&(identical(other.fileName, fileName) || other.fileName == fileName)&&(identical(other.fileSize, fileSize) || other.fileSize == fileSize)&&(identical(other.mimeType, mimeType) || other.mimeType == mimeType)&&(identical(other.totalChunks, totalChunks) || other.totalChunks == totalChunks)&&(identical(other.duration, duration) || other.duration == duration)&&(identical(other.timestamp, timestamp) || other.timestamp == timestamp));
}


@override
int get hashCode => Object.hash(runtimeType,from,fileName,fileSize,mimeType,totalChunks,duration,timestamp);

@override
String toString() {
  return 'FlutterDirectEvent.metadata(from: $from, fileName: $fileName, fileSize: $fileSize, mimeType: $mimeType, totalChunks: $totalChunks, duration: $duration, timestamp: $timestamp)';
}


}

/// @nodoc
abstract mixin class $FlutterDirectEvent_MetadataCopyWith<$Res> implements $FlutterDirectEventCopyWith<$Res> {
  factory $FlutterDirectEvent_MetadataCopyWith(FlutterDirectEvent_Metadata value, $Res Function(FlutterDirectEvent_Metadata) _then) = _$FlutterDirectEvent_MetadataCopyWithImpl;
@useResult
$Res call({
 String from, String fileName, BigInt fileSize, String mimeType, int totalChunks, double? duration, BigInt timestamp
});




}
/// @nodoc
class _$FlutterDirectEvent_MetadataCopyWithImpl<$Res>
    implements $FlutterDirectEvent_MetadataCopyWith<$Res> {
  _$FlutterDirectEvent_MetadataCopyWithImpl(this._self, this._then);

  final FlutterDirectEvent_Metadata _self;
  final $Res Function(FlutterDirectEvent_Metadata) _then;

/// Create a copy of FlutterDirectEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? from = null,Object? fileName = null,Object? fileSize = null,Object? mimeType = null,Object? totalChunks = null,Object? duration = freezed,Object? timestamp = null,}) {
  return _then(FlutterDirectEvent_Metadata(
from: null == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as String,fileName: null == fileName ? _self.fileName : fileName // ignore: cast_nullable_to_non_nullable
as String,fileSize: null == fileSize ? _self.fileSize : fileSize // ignore: cast_nullable_to_non_nullable
as BigInt,mimeType: null == mimeType ? _self.mimeType : mimeType // ignore: cast_nullable_to_non_nullable
as String,totalChunks: null == totalChunks ? _self.totalChunks : totalChunks // ignore: cast_nullable_to_non_nullable
as int,duration: freezed == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as double?,timestamp: null == timestamp ? _self.timestamp : timestamp // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class FlutterDirectEvent_RequestChunk extends FlutterDirectEvent {
  const FlutterDirectEvent_RequestChunk({required this.from, required this.index, required this.timestamp}): super._();
  

 final  String from;
 final  int index;
 final  BigInt timestamp;

/// Create a copy of FlutterDirectEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FlutterDirectEvent_RequestChunkCopyWith<FlutterDirectEvent_RequestChunk> get copyWith => _$FlutterDirectEvent_RequestChunkCopyWithImpl<FlutterDirectEvent_RequestChunk>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlutterDirectEvent_RequestChunk&&(identical(other.from, from) || other.from == from)&&(identical(other.index, index) || other.index == index)&&(identical(other.timestamp, timestamp) || other.timestamp == timestamp));
}


@override
int get hashCode => Object.hash(runtimeType,from,index,timestamp);

@override
String toString() {
  return 'FlutterDirectEvent.requestChunk(from: $from, index: $index, timestamp: $timestamp)';
}


}

/// @nodoc
abstract mixin class $FlutterDirectEvent_RequestChunkCopyWith<$Res> implements $FlutterDirectEventCopyWith<$Res> {
  factory $FlutterDirectEvent_RequestChunkCopyWith(FlutterDirectEvent_RequestChunk value, $Res Function(FlutterDirectEvent_RequestChunk) _then) = _$FlutterDirectEvent_RequestChunkCopyWithImpl;
@useResult
$Res call({
 String from, int index, BigInt timestamp
});




}
/// @nodoc
class _$FlutterDirectEvent_RequestChunkCopyWithImpl<$Res>
    implements $FlutterDirectEvent_RequestChunkCopyWith<$Res> {
  _$FlutterDirectEvent_RequestChunkCopyWithImpl(this._self, this._then);

  final FlutterDirectEvent_RequestChunk _self;
  final $Res Function(FlutterDirectEvent_RequestChunk) _then;

/// Create a copy of FlutterDirectEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? from = null,Object? index = null,Object? timestamp = null,}) {
  return _then(FlutterDirectEvent_RequestChunk(
from: null == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as String,index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as int,timestamp: null == timestamp ? _self.timestamp : timestamp // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class FlutterDirectEvent_Chunk extends FlutterDirectEvent {
  const FlutterDirectEvent_Chunk({required this.from, required this.index, required this.data, required this.timestamp}): super._();
  

 final  String from;
 final  int index;
 final  Uint8List data;
 final  BigInt timestamp;

/// Create a copy of FlutterDirectEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FlutterDirectEvent_ChunkCopyWith<FlutterDirectEvent_Chunk> get copyWith => _$FlutterDirectEvent_ChunkCopyWithImpl<FlutterDirectEvent_Chunk>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlutterDirectEvent_Chunk&&(identical(other.from, from) || other.from == from)&&(identical(other.index, index) || other.index == index)&&const DeepCollectionEquality().equals(other.data, data)&&(identical(other.timestamp, timestamp) || other.timestamp == timestamp));
}


@override
int get hashCode => Object.hash(runtimeType,from,index,const DeepCollectionEquality().hash(data),timestamp);

@override
String toString() {
  return 'FlutterDirectEvent.chunk(from: $from, index: $index, data: $data, timestamp: $timestamp)';
}


}

/// @nodoc
abstract mixin class $FlutterDirectEvent_ChunkCopyWith<$Res> implements $FlutterDirectEventCopyWith<$Res> {
  factory $FlutterDirectEvent_ChunkCopyWith(FlutterDirectEvent_Chunk value, $Res Function(FlutterDirectEvent_Chunk) _then) = _$FlutterDirectEvent_ChunkCopyWithImpl;
@useResult
$Res call({
 String from, int index, Uint8List data, BigInt timestamp
});




}
/// @nodoc
class _$FlutterDirectEvent_ChunkCopyWithImpl<$Res>
    implements $FlutterDirectEvent_ChunkCopyWith<$Res> {
  _$FlutterDirectEvent_ChunkCopyWithImpl(this._self, this._then);

  final FlutterDirectEvent_Chunk _self;
  final $Res Function(FlutterDirectEvent_Chunk) _then;

/// Create a copy of FlutterDirectEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? from = null,Object? index = null,Object? data = null,Object? timestamp = null,}) {
  return _then(FlutterDirectEvent_Chunk(
from: null == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as String,index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as int,data: null == data ? _self.data : data // ignore: cast_nullable_to_non_nullable
as Uint8List,timestamp: null == timestamp ? _self.timestamp : timestamp // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class FlutterDirectEvent_Presence extends FlutterDirectEvent {
  const FlutterDirectEvent_Presence({required this.from, required this.name, required this.timestamp}): super._();
  

 final  String from;
 final  String name;
 final  BigInt timestamp;

/// Create a copy of FlutterDirectEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FlutterDirectEvent_PresenceCopyWith<FlutterDirectEvent_Presence> get copyWith => _$FlutterDirectEvent_PresenceCopyWithImpl<FlutterDirectEvent_Presence>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlutterDirectEvent_Presence&&(identical(other.from, from) || other.from == from)&&(identical(other.name, name) || other.name == name)&&(identical(other.timestamp, timestamp) || other.timestamp == timestamp));
}


@override
int get hashCode => Object.hash(runtimeType,from,name,timestamp);

@override
String toString() {
  return 'FlutterDirectEvent.presence(from: $from, name: $name, timestamp: $timestamp)';
}


}

/// @nodoc
abstract mixin class $FlutterDirectEvent_PresenceCopyWith<$Res> implements $FlutterDirectEventCopyWith<$Res> {
  factory $FlutterDirectEvent_PresenceCopyWith(FlutterDirectEvent_Presence value, $Res Function(FlutterDirectEvent_Presence) _then) = _$FlutterDirectEvent_PresenceCopyWithImpl;
@useResult
$Res call({
 String from, String name, BigInt timestamp
});




}
/// @nodoc
class _$FlutterDirectEvent_PresenceCopyWithImpl<$Res>
    implements $FlutterDirectEvent_PresenceCopyWith<$Res> {
  _$FlutterDirectEvent_PresenceCopyWithImpl(this._self, this._then);

  final FlutterDirectEvent_Presence _self;
  final $Res Function(FlutterDirectEvent_Presence) _then;

/// Create a copy of FlutterDirectEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? from = null,Object? name = null,Object? timestamp = null,}) {
  return _then(FlutterDirectEvent_Presence(
from: null == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,timestamp: null == timestamp ? _self.timestamp : timestamp // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class FlutterDirectEvent_Signal extends FlutterDirectEvent {
  const FlutterDirectEvent_Signal({required this.from, required this.data, required this.timestamp}): super._();
  

 final  String from;
 final  Uint8List data;
 final  BigInt timestamp;

/// Create a copy of FlutterDirectEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FlutterDirectEvent_SignalCopyWith<FlutterDirectEvent_Signal> get copyWith => _$FlutterDirectEvent_SignalCopyWithImpl<FlutterDirectEvent_Signal>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlutterDirectEvent_Signal&&(identical(other.from, from) || other.from == from)&&const DeepCollectionEquality().equals(other.data, data)&&(identical(other.timestamp, timestamp) || other.timestamp == timestamp));
}


@override
int get hashCode => Object.hash(runtimeType,from,const DeepCollectionEquality().hash(data),timestamp);

@override
String toString() {
  return 'FlutterDirectEvent.signal(from: $from, data: $data, timestamp: $timestamp)';
}


}

/// @nodoc
abstract mixin class $FlutterDirectEvent_SignalCopyWith<$Res> implements $FlutterDirectEventCopyWith<$Res> {
  factory $FlutterDirectEvent_SignalCopyWith(FlutterDirectEvent_Signal value, $Res Function(FlutterDirectEvent_Signal) _then) = _$FlutterDirectEvent_SignalCopyWithImpl;
@useResult
$Res call({
 String from, Uint8List data, BigInt timestamp
});




}
/// @nodoc
class _$FlutterDirectEvent_SignalCopyWithImpl<$Res>
    implements $FlutterDirectEvent_SignalCopyWith<$Res> {
  _$FlutterDirectEvent_SignalCopyWithImpl(this._self, this._then);

  final FlutterDirectEvent_Signal _self;
  final $Res Function(FlutterDirectEvent_Signal) _then;

/// Create a copy of FlutterDirectEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? from = null,Object? data = null,Object? timestamp = null,}) {
  return _then(FlutterDirectEvent_Signal(
from: null == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as String,data: null == data ? _self.data : data // ignore: cast_nullable_to_non_nullable
as Uint8List,timestamp: null == timestamp ? _self.timestamp : timestamp // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class FlutterDirectEvent_Error extends FlutterDirectEvent {
  const FlutterDirectEvent_Error({required this.message}): super._();
  

 final  String message;

/// Create a copy of FlutterDirectEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FlutterDirectEvent_ErrorCopyWith<FlutterDirectEvent_Error> get copyWith => _$FlutterDirectEvent_ErrorCopyWithImpl<FlutterDirectEvent_Error>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlutterDirectEvent_Error&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,message);

@override
String toString() {
  return 'FlutterDirectEvent.error(message: $message)';
}


}

/// @nodoc
abstract mixin class $FlutterDirectEvent_ErrorCopyWith<$Res> implements $FlutterDirectEventCopyWith<$Res> {
  factory $FlutterDirectEvent_ErrorCopyWith(FlutterDirectEvent_Error value, $Res Function(FlutterDirectEvent_Error) _then) = _$FlutterDirectEvent_ErrorCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$FlutterDirectEvent_ErrorCopyWithImpl<$Res>
    implements $FlutterDirectEvent_ErrorCopyWith<$Res> {
  _$FlutterDirectEvent_ErrorCopyWithImpl(this._self, this._then);

  final FlutterDirectEvent_Error _self;
  final $Res Function(FlutterDirectEvent_Error) _then;

/// Create a copy of FlutterDirectEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(FlutterDirectEvent_Error(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on

// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'live_flutter_api.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$FlutterLiveEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlutterLiveEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'FlutterLiveEvent()';
}


}

/// @nodoc
class $FlutterLiveEventCopyWith<$Res>  {
$FlutterLiveEventCopyWith(FlutterLiveEvent _, $Res Function(FlutterLiveEvent) __);
}


/// Adds pattern-matching-related methods to [FlutterLiveEvent].
extension FlutterLiveEventPatterns on FlutterLiveEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( FlutterLiveEvent_PeerConnected value)?  peerConnected,TResult Function( FlutterLiveEvent_PeerDisconnected value)?  peerDisconnected,TResult Function( FlutterLiveEvent_CatalogReceived value)?  catalogReceived,TResult Function( FlutterLiveEvent_MetadataReceived value)?  metadataReceived,TResult Function( FlutterLiveEvent_ChunkRequested value)?  chunkRequested,TResult Function( FlutterLiveEvent_ChunkReceived value)?  chunkReceived,TResult Function( FlutterLiveEvent_MetadataRequested value)?  metadataRequested,TResult Function( FlutterLiveEvent_StatsUpdated value)?  statsUpdated,TResult Function( FlutterLiveEvent_Error value)?  error,required TResult orElse(),}){
final _that = this;
switch (_that) {
case FlutterLiveEvent_PeerConnected() when peerConnected != null:
return peerConnected(_that);case FlutterLiveEvent_PeerDisconnected() when peerDisconnected != null:
return peerDisconnected(_that);case FlutterLiveEvent_CatalogReceived() when catalogReceived != null:
return catalogReceived(_that);case FlutterLiveEvent_MetadataReceived() when metadataReceived != null:
return metadataReceived(_that);case FlutterLiveEvent_ChunkRequested() when chunkRequested != null:
return chunkRequested(_that);case FlutterLiveEvent_ChunkReceived() when chunkReceived != null:
return chunkReceived(_that);case FlutterLiveEvent_MetadataRequested() when metadataRequested != null:
return metadataRequested(_that);case FlutterLiveEvent_StatsUpdated() when statsUpdated != null:
return statsUpdated(_that);case FlutterLiveEvent_Error() when error != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( FlutterLiveEvent_PeerConnected value)  peerConnected,required TResult Function( FlutterLiveEvent_PeerDisconnected value)  peerDisconnected,required TResult Function( FlutterLiveEvent_CatalogReceived value)  catalogReceived,required TResult Function( FlutterLiveEvent_MetadataReceived value)  metadataReceived,required TResult Function( FlutterLiveEvent_ChunkRequested value)  chunkRequested,required TResult Function( FlutterLiveEvent_ChunkReceived value)  chunkReceived,required TResult Function( FlutterLiveEvent_MetadataRequested value)  metadataRequested,required TResult Function( FlutterLiveEvent_StatsUpdated value)  statsUpdated,required TResult Function( FlutterLiveEvent_Error value)  error,}){
final _that = this;
switch (_that) {
case FlutterLiveEvent_PeerConnected():
return peerConnected(_that);case FlutterLiveEvent_PeerDisconnected():
return peerDisconnected(_that);case FlutterLiveEvent_CatalogReceived():
return catalogReceived(_that);case FlutterLiveEvent_MetadataReceived():
return metadataReceived(_that);case FlutterLiveEvent_ChunkRequested():
return chunkRequested(_that);case FlutterLiveEvent_ChunkReceived():
return chunkReceived(_that);case FlutterLiveEvent_MetadataRequested():
return metadataRequested(_that);case FlutterLiveEvent_StatsUpdated():
return statsUpdated(_that);case FlutterLiveEvent_Error():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( FlutterLiveEvent_PeerConnected value)?  peerConnected,TResult? Function( FlutterLiveEvent_PeerDisconnected value)?  peerDisconnected,TResult? Function( FlutterLiveEvent_CatalogReceived value)?  catalogReceived,TResult? Function( FlutterLiveEvent_MetadataReceived value)?  metadataReceived,TResult? Function( FlutterLiveEvent_ChunkRequested value)?  chunkRequested,TResult? Function( FlutterLiveEvent_ChunkReceived value)?  chunkReceived,TResult? Function( FlutterLiveEvent_MetadataRequested value)?  metadataRequested,TResult? Function( FlutterLiveEvent_StatsUpdated value)?  statsUpdated,TResult? Function( FlutterLiveEvent_Error value)?  error,}){
final _that = this;
switch (_that) {
case FlutterLiveEvent_PeerConnected() when peerConnected != null:
return peerConnected(_that);case FlutterLiveEvent_PeerDisconnected() when peerDisconnected != null:
return peerDisconnected(_that);case FlutterLiveEvent_CatalogReceived() when catalogReceived != null:
return catalogReceived(_that);case FlutterLiveEvent_MetadataReceived() when metadataReceived != null:
return metadataReceived(_that);case FlutterLiveEvent_ChunkRequested() when chunkRequested != null:
return chunkRequested(_that);case FlutterLiveEvent_ChunkReceived() when chunkReceived != null:
return chunkReceived(_that);case FlutterLiveEvent_MetadataRequested() when metadataRequested != null:
return metadataRequested(_that);case FlutterLiveEvent_StatsUpdated() when statsUpdated != null:
return statsUpdated(_that);case FlutterLiveEvent_Error() when error != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String peerId)?  peerConnected,TResult Function( String peerId)?  peerDisconnected,TResult Function( FlutterCatalog catalog)?  catalogReceived,TResult Function( String from,  String fileName,  BigInt fileSize,  String mimeType,  int totalChunks,  double? duration)?  metadataReceived,TResult Function( String from,  int index)?  chunkRequested,TResult Function( String from,  int index,  Uint8List data)?  chunkReceived,TResult Function( String from)?  metadataRequested,TResult Function( FlutterConnectionStats stats)?  statsUpdated,TResult Function( String message)?  error,required TResult orElse(),}) {final _that = this;
switch (_that) {
case FlutterLiveEvent_PeerConnected() when peerConnected != null:
return peerConnected(_that.peerId);case FlutterLiveEvent_PeerDisconnected() when peerDisconnected != null:
return peerDisconnected(_that.peerId);case FlutterLiveEvent_CatalogReceived() when catalogReceived != null:
return catalogReceived(_that.catalog);case FlutterLiveEvent_MetadataReceived() when metadataReceived != null:
return metadataReceived(_that.from,_that.fileName,_that.fileSize,_that.mimeType,_that.totalChunks,_that.duration);case FlutterLiveEvent_ChunkRequested() when chunkRequested != null:
return chunkRequested(_that.from,_that.index);case FlutterLiveEvent_ChunkReceived() when chunkReceived != null:
return chunkReceived(_that.from,_that.index,_that.data);case FlutterLiveEvent_MetadataRequested() when metadataRequested != null:
return metadataRequested(_that.from);case FlutterLiveEvent_StatsUpdated() when statsUpdated != null:
return statsUpdated(_that.stats);case FlutterLiveEvent_Error() when error != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String peerId)  peerConnected,required TResult Function( String peerId)  peerDisconnected,required TResult Function( FlutterCatalog catalog)  catalogReceived,required TResult Function( String from,  String fileName,  BigInt fileSize,  String mimeType,  int totalChunks,  double? duration)  metadataReceived,required TResult Function( String from,  int index)  chunkRequested,required TResult Function( String from,  int index,  Uint8List data)  chunkReceived,required TResult Function( String from)  metadataRequested,required TResult Function( FlutterConnectionStats stats)  statsUpdated,required TResult Function( String message)  error,}) {final _that = this;
switch (_that) {
case FlutterLiveEvent_PeerConnected():
return peerConnected(_that.peerId);case FlutterLiveEvent_PeerDisconnected():
return peerDisconnected(_that.peerId);case FlutterLiveEvent_CatalogReceived():
return catalogReceived(_that.catalog);case FlutterLiveEvent_MetadataReceived():
return metadataReceived(_that.from,_that.fileName,_that.fileSize,_that.mimeType,_that.totalChunks,_that.duration);case FlutterLiveEvent_ChunkRequested():
return chunkRequested(_that.from,_that.index);case FlutterLiveEvent_ChunkReceived():
return chunkReceived(_that.from,_that.index,_that.data);case FlutterLiveEvent_MetadataRequested():
return metadataRequested(_that.from);case FlutterLiveEvent_StatsUpdated():
return statsUpdated(_that.stats);case FlutterLiveEvent_Error():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String peerId)?  peerConnected,TResult? Function( String peerId)?  peerDisconnected,TResult? Function( FlutterCatalog catalog)?  catalogReceived,TResult? Function( String from,  String fileName,  BigInt fileSize,  String mimeType,  int totalChunks,  double? duration)?  metadataReceived,TResult? Function( String from,  int index)?  chunkRequested,TResult? Function( String from,  int index,  Uint8List data)?  chunkReceived,TResult? Function( String from)?  metadataRequested,TResult? Function( FlutterConnectionStats stats)?  statsUpdated,TResult? Function( String message)?  error,}) {final _that = this;
switch (_that) {
case FlutterLiveEvent_PeerConnected() when peerConnected != null:
return peerConnected(_that.peerId);case FlutterLiveEvent_PeerDisconnected() when peerDisconnected != null:
return peerDisconnected(_that.peerId);case FlutterLiveEvent_CatalogReceived() when catalogReceived != null:
return catalogReceived(_that.catalog);case FlutterLiveEvent_MetadataReceived() when metadataReceived != null:
return metadataReceived(_that.from,_that.fileName,_that.fileSize,_that.mimeType,_that.totalChunks,_that.duration);case FlutterLiveEvent_ChunkRequested() when chunkRequested != null:
return chunkRequested(_that.from,_that.index);case FlutterLiveEvent_ChunkReceived() when chunkReceived != null:
return chunkReceived(_that.from,_that.index,_that.data);case FlutterLiveEvent_MetadataRequested() when metadataRequested != null:
return metadataRequested(_that.from);case FlutterLiveEvent_StatsUpdated() when statsUpdated != null:
return statsUpdated(_that.stats);case FlutterLiveEvent_Error() when error != null:
return error(_that.message);case _:
  return null;

}
}

}

/// @nodoc


class FlutterLiveEvent_PeerConnected extends FlutterLiveEvent {
  const FlutterLiveEvent_PeerConnected({required this.peerId}): super._();
  

 final  String peerId;

/// Create a copy of FlutterLiveEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FlutterLiveEvent_PeerConnectedCopyWith<FlutterLiveEvent_PeerConnected> get copyWith => _$FlutterLiveEvent_PeerConnectedCopyWithImpl<FlutterLiveEvent_PeerConnected>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlutterLiveEvent_PeerConnected&&(identical(other.peerId, peerId) || other.peerId == peerId));
}


@override
int get hashCode => Object.hash(runtimeType,peerId);

@override
String toString() {
  return 'FlutterLiveEvent.peerConnected(peerId: $peerId)';
}


}

/// @nodoc
abstract mixin class $FlutterLiveEvent_PeerConnectedCopyWith<$Res> implements $FlutterLiveEventCopyWith<$Res> {
  factory $FlutterLiveEvent_PeerConnectedCopyWith(FlutterLiveEvent_PeerConnected value, $Res Function(FlutterLiveEvent_PeerConnected) _then) = _$FlutterLiveEvent_PeerConnectedCopyWithImpl;
@useResult
$Res call({
 String peerId
});




}
/// @nodoc
class _$FlutterLiveEvent_PeerConnectedCopyWithImpl<$Res>
    implements $FlutterLiveEvent_PeerConnectedCopyWith<$Res> {
  _$FlutterLiveEvent_PeerConnectedCopyWithImpl(this._self, this._then);

  final FlutterLiveEvent_PeerConnected _self;
  final $Res Function(FlutterLiveEvent_PeerConnected) _then;

/// Create a copy of FlutterLiveEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? peerId = null,}) {
  return _then(FlutterLiveEvent_PeerConnected(
peerId: null == peerId ? _self.peerId : peerId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class FlutterLiveEvent_PeerDisconnected extends FlutterLiveEvent {
  const FlutterLiveEvent_PeerDisconnected({required this.peerId}): super._();
  

 final  String peerId;

/// Create a copy of FlutterLiveEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FlutterLiveEvent_PeerDisconnectedCopyWith<FlutterLiveEvent_PeerDisconnected> get copyWith => _$FlutterLiveEvent_PeerDisconnectedCopyWithImpl<FlutterLiveEvent_PeerDisconnected>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlutterLiveEvent_PeerDisconnected&&(identical(other.peerId, peerId) || other.peerId == peerId));
}


@override
int get hashCode => Object.hash(runtimeType,peerId);

@override
String toString() {
  return 'FlutterLiveEvent.peerDisconnected(peerId: $peerId)';
}


}

/// @nodoc
abstract mixin class $FlutterLiveEvent_PeerDisconnectedCopyWith<$Res> implements $FlutterLiveEventCopyWith<$Res> {
  factory $FlutterLiveEvent_PeerDisconnectedCopyWith(FlutterLiveEvent_PeerDisconnected value, $Res Function(FlutterLiveEvent_PeerDisconnected) _then) = _$FlutterLiveEvent_PeerDisconnectedCopyWithImpl;
@useResult
$Res call({
 String peerId
});




}
/// @nodoc
class _$FlutterLiveEvent_PeerDisconnectedCopyWithImpl<$Res>
    implements $FlutterLiveEvent_PeerDisconnectedCopyWith<$Res> {
  _$FlutterLiveEvent_PeerDisconnectedCopyWithImpl(this._self, this._then);

  final FlutterLiveEvent_PeerDisconnected _self;
  final $Res Function(FlutterLiveEvent_PeerDisconnected) _then;

/// Create a copy of FlutterLiveEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? peerId = null,}) {
  return _then(FlutterLiveEvent_PeerDisconnected(
peerId: null == peerId ? _self.peerId : peerId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class FlutterLiveEvent_CatalogReceived extends FlutterLiveEvent {
  const FlutterLiveEvent_CatalogReceived({required this.catalog}): super._();
  

 final  FlutterCatalog catalog;

/// Create a copy of FlutterLiveEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FlutterLiveEvent_CatalogReceivedCopyWith<FlutterLiveEvent_CatalogReceived> get copyWith => _$FlutterLiveEvent_CatalogReceivedCopyWithImpl<FlutterLiveEvent_CatalogReceived>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlutterLiveEvent_CatalogReceived&&(identical(other.catalog, catalog) || other.catalog == catalog));
}


@override
int get hashCode => Object.hash(runtimeType,catalog);

@override
String toString() {
  return 'FlutterLiveEvent.catalogReceived(catalog: $catalog)';
}


}

/// @nodoc
abstract mixin class $FlutterLiveEvent_CatalogReceivedCopyWith<$Res> implements $FlutterLiveEventCopyWith<$Res> {
  factory $FlutterLiveEvent_CatalogReceivedCopyWith(FlutterLiveEvent_CatalogReceived value, $Res Function(FlutterLiveEvent_CatalogReceived) _then) = _$FlutterLiveEvent_CatalogReceivedCopyWithImpl;
@useResult
$Res call({
 FlutterCatalog catalog
});




}
/// @nodoc
class _$FlutterLiveEvent_CatalogReceivedCopyWithImpl<$Res>
    implements $FlutterLiveEvent_CatalogReceivedCopyWith<$Res> {
  _$FlutterLiveEvent_CatalogReceivedCopyWithImpl(this._self, this._then);

  final FlutterLiveEvent_CatalogReceived _self;
  final $Res Function(FlutterLiveEvent_CatalogReceived) _then;

/// Create a copy of FlutterLiveEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? catalog = null,}) {
  return _then(FlutterLiveEvent_CatalogReceived(
catalog: null == catalog ? _self.catalog : catalog // ignore: cast_nullable_to_non_nullable
as FlutterCatalog,
  ));
}


}

/// @nodoc


class FlutterLiveEvent_MetadataReceived extends FlutterLiveEvent {
  const FlutterLiveEvent_MetadataReceived({required this.from, required this.fileName, required this.fileSize, required this.mimeType, required this.totalChunks, this.duration}): super._();
  

 final  String from;
 final  String fileName;
 final  BigInt fileSize;
 final  String mimeType;
 final  int totalChunks;
 final  double? duration;

/// Create a copy of FlutterLiveEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FlutterLiveEvent_MetadataReceivedCopyWith<FlutterLiveEvent_MetadataReceived> get copyWith => _$FlutterLiveEvent_MetadataReceivedCopyWithImpl<FlutterLiveEvent_MetadataReceived>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlutterLiveEvent_MetadataReceived&&(identical(other.from, from) || other.from == from)&&(identical(other.fileName, fileName) || other.fileName == fileName)&&(identical(other.fileSize, fileSize) || other.fileSize == fileSize)&&(identical(other.mimeType, mimeType) || other.mimeType == mimeType)&&(identical(other.totalChunks, totalChunks) || other.totalChunks == totalChunks)&&(identical(other.duration, duration) || other.duration == duration));
}


@override
int get hashCode => Object.hash(runtimeType,from,fileName,fileSize,mimeType,totalChunks,duration);

@override
String toString() {
  return 'FlutterLiveEvent.metadataReceived(from: $from, fileName: $fileName, fileSize: $fileSize, mimeType: $mimeType, totalChunks: $totalChunks, duration: $duration)';
}


}

/// @nodoc
abstract mixin class $FlutterLiveEvent_MetadataReceivedCopyWith<$Res> implements $FlutterLiveEventCopyWith<$Res> {
  factory $FlutterLiveEvent_MetadataReceivedCopyWith(FlutterLiveEvent_MetadataReceived value, $Res Function(FlutterLiveEvent_MetadataReceived) _then) = _$FlutterLiveEvent_MetadataReceivedCopyWithImpl;
@useResult
$Res call({
 String from, String fileName, BigInt fileSize, String mimeType, int totalChunks, double? duration
});




}
/// @nodoc
class _$FlutterLiveEvent_MetadataReceivedCopyWithImpl<$Res>
    implements $FlutterLiveEvent_MetadataReceivedCopyWith<$Res> {
  _$FlutterLiveEvent_MetadataReceivedCopyWithImpl(this._self, this._then);

  final FlutterLiveEvent_MetadataReceived _self;
  final $Res Function(FlutterLiveEvent_MetadataReceived) _then;

/// Create a copy of FlutterLiveEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? from = null,Object? fileName = null,Object? fileSize = null,Object? mimeType = null,Object? totalChunks = null,Object? duration = freezed,}) {
  return _then(FlutterLiveEvent_MetadataReceived(
from: null == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as String,fileName: null == fileName ? _self.fileName : fileName // ignore: cast_nullable_to_non_nullable
as String,fileSize: null == fileSize ? _self.fileSize : fileSize // ignore: cast_nullable_to_non_nullable
as BigInt,mimeType: null == mimeType ? _self.mimeType : mimeType // ignore: cast_nullable_to_non_nullable
as String,totalChunks: null == totalChunks ? _self.totalChunks : totalChunks // ignore: cast_nullable_to_non_nullable
as int,duration: freezed == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}


}

/// @nodoc


class FlutterLiveEvent_ChunkRequested extends FlutterLiveEvent {
  const FlutterLiveEvent_ChunkRequested({required this.from, required this.index}): super._();
  

 final  String from;
 final  int index;

/// Create a copy of FlutterLiveEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FlutterLiveEvent_ChunkRequestedCopyWith<FlutterLiveEvent_ChunkRequested> get copyWith => _$FlutterLiveEvent_ChunkRequestedCopyWithImpl<FlutterLiveEvent_ChunkRequested>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlutterLiveEvent_ChunkRequested&&(identical(other.from, from) || other.from == from)&&(identical(other.index, index) || other.index == index));
}


@override
int get hashCode => Object.hash(runtimeType,from,index);

@override
String toString() {
  return 'FlutterLiveEvent.chunkRequested(from: $from, index: $index)';
}


}

/// @nodoc
abstract mixin class $FlutterLiveEvent_ChunkRequestedCopyWith<$Res> implements $FlutterLiveEventCopyWith<$Res> {
  factory $FlutterLiveEvent_ChunkRequestedCopyWith(FlutterLiveEvent_ChunkRequested value, $Res Function(FlutterLiveEvent_ChunkRequested) _then) = _$FlutterLiveEvent_ChunkRequestedCopyWithImpl;
@useResult
$Res call({
 String from, int index
});




}
/// @nodoc
class _$FlutterLiveEvent_ChunkRequestedCopyWithImpl<$Res>
    implements $FlutterLiveEvent_ChunkRequestedCopyWith<$Res> {
  _$FlutterLiveEvent_ChunkRequestedCopyWithImpl(this._self, this._then);

  final FlutterLiveEvent_ChunkRequested _self;
  final $Res Function(FlutterLiveEvent_ChunkRequested) _then;

/// Create a copy of FlutterLiveEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? from = null,Object? index = null,}) {
  return _then(FlutterLiveEvent_ChunkRequested(
from: null == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as String,index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class FlutterLiveEvent_ChunkReceived extends FlutterLiveEvent {
  const FlutterLiveEvent_ChunkReceived({required this.from, required this.index, required this.data}): super._();
  

 final  String from;
 final  int index;
 final  Uint8List data;

/// Create a copy of FlutterLiveEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FlutterLiveEvent_ChunkReceivedCopyWith<FlutterLiveEvent_ChunkReceived> get copyWith => _$FlutterLiveEvent_ChunkReceivedCopyWithImpl<FlutterLiveEvent_ChunkReceived>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlutterLiveEvent_ChunkReceived&&(identical(other.from, from) || other.from == from)&&(identical(other.index, index) || other.index == index)&&const DeepCollectionEquality().equals(other.data, data));
}


@override
int get hashCode => Object.hash(runtimeType,from,index,const DeepCollectionEquality().hash(data));

@override
String toString() {
  return 'FlutterLiveEvent.chunkReceived(from: $from, index: $index, data: $data)';
}


}

/// @nodoc
abstract mixin class $FlutterLiveEvent_ChunkReceivedCopyWith<$Res> implements $FlutterLiveEventCopyWith<$Res> {
  factory $FlutterLiveEvent_ChunkReceivedCopyWith(FlutterLiveEvent_ChunkReceived value, $Res Function(FlutterLiveEvent_ChunkReceived) _then) = _$FlutterLiveEvent_ChunkReceivedCopyWithImpl;
@useResult
$Res call({
 String from, int index, Uint8List data
});




}
/// @nodoc
class _$FlutterLiveEvent_ChunkReceivedCopyWithImpl<$Res>
    implements $FlutterLiveEvent_ChunkReceivedCopyWith<$Res> {
  _$FlutterLiveEvent_ChunkReceivedCopyWithImpl(this._self, this._then);

  final FlutterLiveEvent_ChunkReceived _self;
  final $Res Function(FlutterLiveEvent_ChunkReceived) _then;

/// Create a copy of FlutterLiveEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? from = null,Object? index = null,Object? data = null,}) {
  return _then(FlutterLiveEvent_ChunkReceived(
from: null == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as String,index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as int,data: null == data ? _self.data : data // ignore: cast_nullable_to_non_nullable
as Uint8List,
  ));
}


}

/// @nodoc


class FlutterLiveEvent_MetadataRequested extends FlutterLiveEvent {
  const FlutterLiveEvent_MetadataRequested({required this.from}): super._();
  

 final  String from;

/// Create a copy of FlutterLiveEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FlutterLiveEvent_MetadataRequestedCopyWith<FlutterLiveEvent_MetadataRequested> get copyWith => _$FlutterLiveEvent_MetadataRequestedCopyWithImpl<FlutterLiveEvent_MetadataRequested>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlutterLiveEvent_MetadataRequested&&(identical(other.from, from) || other.from == from));
}


@override
int get hashCode => Object.hash(runtimeType,from);

@override
String toString() {
  return 'FlutterLiveEvent.metadataRequested(from: $from)';
}


}

/// @nodoc
abstract mixin class $FlutterLiveEvent_MetadataRequestedCopyWith<$Res> implements $FlutterLiveEventCopyWith<$Res> {
  factory $FlutterLiveEvent_MetadataRequestedCopyWith(FlutterLiveEvent_MetadataRequested value, $Res Function(FlutterLiveEvent_MetadataRequested) _then) = _$FlutterLiveEvent_MetadataRequestedCopyWithImpl;
@useResult
$Res call({
 String from
});




}
/// @nodoc
class _$FlutterLiveEvent_MetadataRequestedCopyWithImpl<$Res>
    implements $FlutterLiveEvent_MetadataRequestedCopyWith<$Res> {
  _$FlutterLiveEvent_MetadataRequestedCopyWithImpl(this._self, this._then);

  final FlutterLiveEvent_MetadataRequested _self;
  final $Res Function(FlutterLiveEvent_MetadataRequested) _then;

/// Create a copy of FlutterLiveEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? from = null,}) {
  return _then(FlutterLiveEvent_MetadataRequested(
from: null == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class FlutterLiveEvent_StatsUpdated extends FlutterLiveEvent {
  const FlutterLiveEvent_StatsUpdated({required this.stats}): super._();
  

 final  FlutterConnectionStats stats;

/// Create a copy of FlutterLiveEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FlutterLiveEvent_StatsUpdatedCopyWith<FlutterLiveEvent_StatsUpdated> get copyWith => _$FlutterLiveEvent_StatsUpdatedCopyWithImpl<FlutterLiveEvent_StatsUpdated>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlutterLiveEvent_StatsUpdated&&(identical(other.stats, stats) || other.stats == stats));
}


@override
int get hashCode => Object.hash(runtimeType,stats);

@override
String toString() {
  return 'FlutterLiveEvent.statsUpdated(stats: $stats)';
}


}

/// @nodoc
abstract mixin class $FlutterLiveEvent_StatsUpdatedCopyWith<$Res> implements $FlutterLiveEventCopyWith<$Res> {
  factory $FlutterLiveEvent_StatsUpdatedCopyWith(FlutterLiveEvent_StatsUpdated value, $Res Function(FlutterLiveEvent_StatsUpdated) _then) = _$FlutterLiveEvent_StatsUpdatedCopyWithImpl;
@useResult
$Res call({
 FlutterConnectionStats stats
});




}
/// @nodoc
class _$FlutterLiveEvent_StatsUpdatedCopyWithImpl<$Res>
    implements $FlutterLiveEvent_StatsUpdatedCopyWith<$Res> {
  _$FlutterLiveEvent_StatsUpdatedCopyWithImpl(this._self, this._then);

  final FlutterLiveEvent_StatsUpdated _self;
  final $Res Function(FlutterLiveEvent_StatsUpdated) _then;

/// Create a copy of FlutterLiveEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? stats = null,}) {
  return _then(FlutterLiveEvent_StatsUpdated(
stats: null == stats ? _self.stats : stats // ignore: cast_nullable_to_non_nullable
as FlutterConnectionStats,
  ));
}


}

/// @nodoc


class FlutterLiveEvent_Error extends FlutterLiveEvent {
  const FlutterLiveEvent_Error({required this.message}): super._();
  

 final  String message;

/// Create a copy of FlutterLiveEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FlutterLiveEvent_ErrorCopyWith<FlutterLiveEvent_Error> get copyWith => _$FlutterLiveEvent_ErrorCopyWithImpl<FlutterLiveEvent_Error>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlutterLiveEvent_Error&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,message);

@override
String toString() {
  return 'FlutterLiveEvent.error(message: $message)';
}


}

/// @nodoc
abstract mixin class $FlutterLiveEvent_ErrorCopyWith<$Res> implements $FlutterLiveEventCopyWith<$Res> {
  factory $FlutterLiveEvent_ErrorCopyWith(FlutterLiveEvent_Error value, $Res Function(FlutterLiveEvent_Error) _then) = _$FlutterLiveEvent_ErrorCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$FlutterLiveEvent_ErrorCopyWithImpl<$Res>
    implements $FlutterLiveEvent_ErrorCopyWith<$Res> {
  _$FlutterLiveEvent_ErrorCopyWithImpl(this._self, this._then);

  final FlutterLiveEvent_Error _self;
  final $Res Function(FlutterLiveEvent_Error) _then;

/// Create a copy of FlutterLiveEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(FlutterLiveEvent_Error(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on

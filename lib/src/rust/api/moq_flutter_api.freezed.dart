// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'moq_flutter_api.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$FlutterFilterType {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlutterFilterType);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'FlutterFilterType()';
}


}

/// @nodoc
class $FlutterFilterTypeCopyWith<$Res>  {
$FlutterFilterTypeCopyWith(FlutterFilterType _, $Res Function(FlutterFilterType) __);
}


/// Adds pattern-matching-related methods to [FlutterFilterType].
extension FlutterFilterTypePatterns on FlutterFilterType {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( FlutterFilterType_LatestGroup value)?  latestGroup,TResult Function( FlutterFilterType_LatestObject value)?  latestObject,TResult Function( FlutterFilterType_NextGroup value)?  nextGroup,TResult Function( FlutterFilterType_AbsoluteStart value)?  absoluteStart,TResult Function( FlutterFilterType_AbsoluteRange value)?  absoluteRange,required TResult orElse(),}){
final _that = this;
switch (_that) {
case FlutterFilterType_LatestGroup() when latestGroup != null:
return latestGroup(_that);case FlutterFilterType_LatestObject() when latestObject != null:
return latestObject(_that);case FlutterFilterType_NextGroup() when nextGroup != null:
return nextGroup(_that);case FlutterFilterType_AbsoluteStart() when absoluteStart != null:
return absoluteStart(_that);case FlutterFilterType_AbsoluteRange() when absoluteRange != null:
return absoluteRange(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( FlutterFilterType_LatestGroup value)  latestGroup,required TResult Function( FlutterFilterType_LatestObject value)  latestObject,required TResult Function( FlutterFilterType_NextGroup value)  nextGroup,required TResult Function( FlutterFilterType_AbsoluteStart value)  absoluteStart,required TResult Function( FlutterFilterType_AbsoluteRange value)  absoluteRange,}){
final _that = this;
switch (_that) {
case FlutterFilterType_LatestGroup():
return latestGroup(_that);case FlutterFilterType_LatestObject():
return latestObject(_that);case FlutterFilterType_NextGroup():
return nextGroup(_that);case FlutterFilterType_AbsoluteStart():
return absoluteStart(_that);case FlutterFilterType_AbsoluteRange():
return absoluteRange(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( FlutterFilterType_LatestGroup value)?  latestGroup,TResult? Function( FlutterFilterType_LatestObject value)?  latestObject,TResult? Function( FlutterFilterType_NextGroup value)?  nextGroup,TResult? Function( FlutterFilterType_AbsoluteStart value)?  absoluteStart,TResult? Function( FlutterFilterType_AbsoluteRange value)?  absoluteRange,}){
final _that = this;
switch (_that) {
case FlutterFilterType_LatestGroup() when latestGroup != null:
return latestGroup(_that);case FlutterFilterType_LatestObject() when latestObject != null:
return latestObject(_that);case FlutterFilterType_NextGroup() when nextGroup != null:
return nextGroup(_that);case FlutterFilterType_AbsoluteStart() when absoluteStart != null:
return absoluteStart(_that);case FlutterFilterType_AbsoluteRange() when absoluteRange != null:
return absoluteRange(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  latestGroup,TResult Function()?  latestObject,TResult Function()?  nextGroup,TResult Function( BigInt startGroup,  BigInt startObject)?  absoluteStart,TResult Function( BigInt startGroup,  BigInt startObject,  BigInt endGroup,  BigInt? endObject)?  absoluteRange,required TResult orElse(),}) {final _that = this;
switch (_that) {
case FlutterFilterType_LatestGroup() when latestGroup != null:
return latestGroup();case FlutterFilterType_LatestObject() when latestObject != null:
return latestObject();case FlutterFilterType_NextGroup() when nextGroup != null:
return nextGroup();case FlutterFilterType_AbsoluteStart() when absoluteStart != null:
return absoluteStart(_that.startGroup,_that.startObject);case FlutterFilterType_AbsoluteRange() when absoluteRange != null:
return absoluteRange(_that.startGroup,_that.startObject,_that.endGroup,_that.endObject);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  latestGroup,required TResult Function()  latestObject,required TResult Function()  nextGroup,required TResult Function( BigInt startGroup,  BigInt startObject)  absoluteStart,required TResult Function( BigInt startGroup,  BigInt startObject,  BigInt endGroup,  BigInt? endObject)  absoluteRange,}) {final _that = this;
switch (_that) {
case FlutterFilterType_LatestGroup():
return latestGroup();case FlutterFilterType_LatestObject():
return latestObject();case FlutterFilterType_NextGroup():
return nextGroup();case FlutterFilterType_AbsoluteStart():
return absoluteStart(_that.startGroup,_that.startObject);case FlutterFilterType_AbsoluteRange():
return absoluteRange(_that.startGroup,_that.startObject,_that.endGroup,_that.endObject);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  latestGroup,TResult? Function()?  latestObject,TResult? Function()?  nextGroup,TResult? Function( BigInt startGroup,  BigInt startObject)?  absoluteStart,TResult? Function( BigInt startGroup,  BigInt startObject,  BigInt endGroup,  BigInt? endObject)?  absoluteRange,}) {final _that = this;
switch (_that) {
case FlutterFilterType_LatestGroup() when latestGroup != null:
return latestGroup();case FlutterFilterType_LatestObject() when latestObject != null:
return latestObject();case FlutterFilterType_NextGroup() when nextGroup != null:
return nextGroup();case FlutterFilterType_AbsoluteStart() when absoluteStart != null:
return absoluteStart(_that.startGroup,_that.startObject);case FlutterFilterType_AbsoluteRange() when absoluteRange != null:
return absoluteRange(_that.startGroup,_that.startObject,_that.endGroup,_that.endObject);case _:
  return null;

}
}

}

/// @nodoc


class FlutterFilterType_LatestGroup extends FlutterFilterType {
  const FlutterFilterType_LatestGroup(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlutterFilterType_LatestGroup);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'FlutterFilterType.latestGroup()';
}


}




/// @nodoc


class FlutterFilterType_LatestObject extends FlutterFilterType {
  const FlutterFilterType_LatestObject(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlutterFilterType_LatestObject);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'FlutterFilterType.latestObject()';
}


}




/// @nodoc


class FlutterFilterType_NextGroup extends FlutterFilterType {
  const FlutterFilterType_NextGroup(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlutterFilterType_NextGroup);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'FlutterFilterType.nextGroup()';
}


}




/// @nodoc


class FlutterFilterType_AbsoluteStart extends FlutterFilterType {
  const FlutterFilterType_AbsoluteStart({required this.startGroup, required this.startObject}): super._();
  

 final  BigInt startGroup;
 final  BigInt startObject;

/// Create a copy of FlutterFilterType
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FlutterFilterType_AbsoluteStartCopyWith<FlutterFilterType_AbsoluteStart> get copyWith => _$FlutterFilterType_AbsoluteStartCopyWithImpl<FlutterFilterType_AbsoluteStart>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlutterFilterType_AbsoluteStart&&(identical(other.startGroup, startGroup) || other.startGroup == startGroup)&&(identical(other.startObject, startObject) || other.startObject == startObject));
}


@override
int get hashCode => Object.hash(runtimeType,startGroup,startObject);

@override
String toString() {
  return 'FlutterFilterType.absoluteStart(startGroup: $startGroup, startObject: $startObject)';
}


}

/// @nodoc
abstract mixin class $FlutterFilterType_AbsoluteStartCopyWith<$Res> implements $FlutterFilterTypeCopyWith<$Res> {
  factory $FlutterFilterType_AbsoluteStartCopyWith(FlutterFilterType_AbsoluteStart value, $Res Function(FlutterFilterType_AbsoluteStart) _then) = _$FlutterFilterType_AbsoluteStartCopyWithImpl;
@useResult
$Res call({
 BigInt startGroup, BigInt startObject
});




}
/// @nodoc
class _$FlutterFilterType_AbsoluteStartCopyWithImpl<$Res>
    implements $FlutterFilterType_AbsoluteStartCopyWith<$Res> {
  _$FlutterFilterType_AbsoluteStartCopyWithImpl(this._self, this._then);

  final FlutterFilterType_AbsoluteStart _self;
  final $Res Function(FlutterFilterType_AbsoluteStart) _then;

/// Create a copy of FlutterFilterType
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? startGroup = null,Object? startObject = null,}) {
  return _then(FlutterFilterType_AbsoluteStart(
startGroup: null == startGroup ? _self.startGroup : startGroup // ignore: cast_nullable_to_non_nullable
as BigInt,startObject: null == startObject ? _self.startObject : startObject // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class FlutterFilterType_AbsoluteRange extends FlutterFilterType {
  const FlutterFilterType_AbsoluteRange({required this.startGroup, required this.startObject, required this.endGroup, this.endObject}): super._();
  

 final  BigInt startGroup;
 final  BigInt startObject;
 final  BigInt endGroup;
 final  BigInt? endObject;

/// Create a copy of FlutterFilterType
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FlutterFilterType_AbsoluteRangeCopyWith<FlutterFilterType_AbsoluteRange> get copyWith => _$FlutterFilterType_AbsoluteRangeCopyWithImpl<FlutterFilterType_AbsoluteRange>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlutterFilterType_AbsoluteRange&&(identical(other.startGroup, startGroup) || other.startGroup == startGroup)&&(identical(other.startObject, startObject) || other.startObject == startObject)&&(identical(other.endGroup, endGroup) || other.endGroup == endGroup)&&(identical(other.endObject, endObject) || other.endObject == endObject));
}


@override
int get hashCode => Object.hash(runtimeType,startGroup,startObject,endGroup,endObject);

@override
String toString() {
  return 'FlutterFilterType.absoluteRange(startGroup: $startGroup, startObject: $startObject, endGroup: $endGroup, endObject: $endObject)';
}


}

/// @nodoc
abstract mixin class $FlutterFilterType_AbsoluteRangeCopyWith<$Res> implements $FlutterFilterTypeCopyWith<$Res> {
  factory $FlutterFilterType_AbsoluteRangeCopyWith(FlutterFilterType_AbsoluteRange value, $Res Function(FlutterFilterType_AbsoluteRange) _then) = _$FlutterFilterType_AbsoluteRangeCopyWithImpl;
@useResult
$Res call({
 BigInt startGroup, BigInt startObject, BigInt endGroup, BigInt? endObject
});




}
/// @nodoc
class _$FlutterFilterType_AbsoluteRangeCopyWithImpl<$Res>
    implements $FlutterFilterType_AbsoluteRangeCopyWith<$Res> {
  _$FlutterFilterType_AbsoluteRangeCopyWithImpl(this._self, this._then);

  final FlutterFilterType_AbsoluteRange _self;
  final $Res Function(FlutterFilterType_AbsoluteRange) _then;

/// Create a copy of FlutterFilterType
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? startGroup = null,Object? startObject = null,Object? endGroup = null,Object? endObject = freezed,}) {
  return _then(FlutterFilterType_AbsoluteRange(
startGroup: null == startGroup ? _self.startGroup : startGroup // ignore: cast_nullable_to_non_nullable
as BigInt,startObject: null == startObject ? _self.startObject : startObject // ignore: cast_nullable_to_non_nullable
as BigInt,endGroup: null == endGroup ? _self.endGroup : endGroup // ignore: cast_nullable_to_non_nullable
as BigInt,endObject: freezed == endObject ? _self.endObject : endObject // ignore: cast_nullable_to_non_nullable
as BigInt?,
  ));
}


}

// dart format on

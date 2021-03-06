module mir.ndslice.internal;

import std.traits;
import std.meta; //: AliasSeq, anySatisfy, Filter, Reverse;
import mir.ndslice : Slice;

version(LDC)
{
    static import ldc.attributes;
    alias fastmath = ldc.attributes.fastmath;
}
else
{
    alias fastmath = fastmathDummy;
}

enum FastmathDummy { init }
FastmathDummy fastmathDummy() { return FastmathDummy.init; }

alias RangeOf(T : Slice!(N, Range), size_t N, Range) = Range;

template isMemory(T)
{
    import mir.ndslice.slice : PtrTuple;
    import mir.ndslice.algorithm : Map, Pack;
    static if (isPointer!T)
        enum isMemory = true;
    else
    static if (is(T : Map!(Range, fun), Range, alias fun))
        enum isMemory = .isMemory!Range;
    else
    static if (__traits(compiles, __traits(isSame, PtrTuple, TemplateOf!(TemplateOf!T))))
        static if (__traits(isSame, PtrTuple, TemplateOf!(TemplateOf!T)))
            enum isMemory = allSatisfy!(.isMemory, TemplateArgsOf!T);
        else
            enum isMemory = false;
    else
        enum isMemory = false;
}

unittest
{
    import mir.ndslice.slice : PtrTuple;
    import mir.ndslice.algorithm : Map;
    static assert(isMemory!(int*));
    alias R = PtrTuple!("a", "b");
    alias F = R!(double*, double*);
    static assert(isMemory!F);
    static assert(isMemory!(Map!(F, a => a)));
}

enum indexError(size_t pos, size_t N) =
    "index at position " ~ pos.stringof
    ~ " from the range [0 .." ~ N.stringof ~ ")"
    ~ " must be less than corresponding length.";

enum indexStrideCode = q{
    static if (_indexes.length)
    {
        size_t stride = _strides[0] * _indexes[0];
        assert(_indexes[0] < _lengths[0], indexError!(0, N));
        foreach (i; Iota!(1, N)) //static
        {
            assert(_indexes[i] < _lengths[i], indexError!(i, N));
            stride += _strides[i] * _indexes[i];
        }
        return stride;
    }
    else
    {
        return 0;
    }
};

enum mathIndexStrideCode = q{
    static if (_indexes.length)
    {
        size_t stride = _strides[0] * _indexes[N - 1];
        assert(_indexes[N - 1] < _lengths[0], indexError!(N - 1, N));
        foreach_reverse (i; Iota!(0, N - 1)) //static
        {
            assert(_indexes[i] < _lengths[N - 1 - i], indexError!(i, N));
            stride += _strides[N - 1 - i] * _indexes[i];
        }
        return stride;
    }
    else
    {
        return 0;
    }
};

enum string tailErrorMessage(
    string fun = __FUNCTION__,
    string pfun = __PRETTY_FUNCTION__) =
"
- - -
Error in function
" ~ fun ~ "
- - -
Function prototype
" ~ pfun ~ "
_____";

mixin template _DefineRet()
{
    alias Ret = typeof(return);
    static if (hasElaborateAssign!(Ret.PureRange))
        Ret ret;
    else
        Ret ret = void;
}

mixin template DimensionsCountCTError()
{
    static assert(Dimensions.length <= N,
        "Dimensions list length = " ~ Dimensions.length.stringof
        ~ " should be less than or equal to N = " ~ N.stringof
        ~ tailErrorMessage!());
}

enum DimensionsCountRTError = q{
    assert(dimensions.length <= N,
        "Dimensions list length should be less than or equal to N = " ~ N.stringof
        ~ tailErrorMessage!());
};

mixin template DimensionCTError()
{
    static assert(dimension >= 0,
        "dimension = " ~ dimension.stringof ~ " at position "
        ~ i.stringof ~ " should be greater than or equal to 0"
        ~ tailErrorMessage!());
    static assert(dimension < N,
        "dimension = " ~ dimension.stringof ~ " at position "
        ~ i.stringof ~ " should be less than N = " ~ N.stringof
        ~ tailErrorMessage!());
}

enum DimensionRTError = q{
    static if (isSigned!(typeof(dimension)))
    assert(dimension >= 0, "dimension should be greater than or equal to 0"
        ~ tailErrorMessage!());
    assert(dimension < N, "dimension should be less than N = " ~ N.stringof
        ~ tailErrorMessage!());
};

private alias IncFront(Seq...) = AliasSeq!(Seq[0] + 1, Seq[1 .. $]);

private alias DecFront(Seq...) = AliasSeq!(Seq[0] - 1, Seq[1 .. $]);

private enum bool isNotZero(alias t) = t != 0;

alias NSeqEvert(Seq...) = Filter!(isNotZero, DecFront!(Reverse!(IncFront!Seq)));

alias Parts(Seq...) = DecAll!(IncFront!Seq);

alias Snowball(Seq...) = AliasSeq!(size_t.init, SnowballImpl!(size_t.init, Seq));

private template SnowballImpl(size_t val, Seq...)
{
    static if (Seq.length == 0)
        alias SnowballImpl = AliasSeq!();
    else
        alias SnowballImpl = AliasSeq!(Seq[0] + val, SnowballImpl!(Seq[0] +  val, Seq[1 .. $]));
}

private template DecAll(Seq...)
{
    static if (Seq.length == 0)
        alias DecAll = AliasSeq!();
    else
        alias DecAll = AliasSeq!(Seq[0] - 1, DecAll!(Seq[1 .. $]));
}

template SliceFromSeq(Range, Seq...)
{
    static if (Seq.length == 0)
        alias SliceFromSeq = Range;
    else
    {
        import mir.ndslice.slice : Slice;
        alias SliceFromSeq = SliceFromSeq!(Slice!(Seq[$ - 1], Range), Seq[0 .. $ - 1]);
    }
}

template DynamicArrayDimensionsCount(T)
{
    static if (isDynamicArray!T)
        enum size_t DynamicArrayDimensionsCount = 1 + DynamicArrayDimensionsCount!(typeof(T.init[0]));
    else
        enum size_t DynamicArrayDimensionsCount = 0;
}

bool isPermutation(size_t N)(auto ref in size_t[N] perm)
{
    int[N] mask;
    return isValidPartialPermutationImpl(perm, mask);
}

unittest
{
    assert(isPermutation([0, 1]));
    // all numbers 0..N-1 need to be part of the permutation
    assert(!isPermutation([1, 2]));
    assert(!isPermutation([0, 2]));
    // duplicates are not allowed
    assert(!isPermutation([0, 1, 1]));

    size_t[0] emptyArr;
    // empty permutations are not allowed either
    assert(!isPermutation(emptyArr));
}

bool isValidPartialPermutation(size_t N)(in size_t[] perm)
{
    int[N] mask;
    return isValidPartialPermutationImpl(perm, mask);
}

private bool isValidPartialPermutationImpl(size_t N)(in size_t[] perm, ref int[N] mask)
{
    if (perm.length == 0)
        return false;
    foreach (j; perm)
    {
        if (j >= N)
            return false;
        if (mask[j]) //duplicate
            return false;
        mask[j] = true;
    }
    return true;
}

enum isIndex(I) = is(I : size_t);
enum is_Slice(S) = is(S : _Slice);

private enum isReference(P) =
    hasIndirections!P
    || isFunctionPointer!P
    || is(P == interface);

enum hasReference(T) = anySatisfy!(isReference, RepresentationTypeTuple!T);

alias ImplicitlyUnqual(T) = Select!(isImplicitlyConvertible!(T, Unqual!T), Unqual!T, T);

//TODO: replace with `static foreach`
template Iota(size_t i, size_t j)
{
    static assert(i <= j, "Iota: i should be less than or equal to j");
    static if (i == j)
        alias Iota = AliasSeq!();
    else
        alias Iota = AliasSeq!(i, Iota!(i + 1, j));
}

size_t lengthsProduct(size_t N)(auto ref in size_t[N] lengths)
{
    size_t length = lengths[0];
    foreach (i; Iota!(1, N))
            length *= lengths[i];
    return length;
}

pure nothrow unittest
{
    const size_t[3] lengths = [3, 4, 5];
    assert(lengthsProduct(lengths) == 60);
    assert(lengthsProduct([3, 4, 5]) == 60);
}

struct _Slice { size_t i, j; }

function out = imnlmfilt(img, varargin)
% IMNLMFILT  Compatibility shim: fall back to imgaussfilt
    out = imgaussfilt(img, 1.2);
end

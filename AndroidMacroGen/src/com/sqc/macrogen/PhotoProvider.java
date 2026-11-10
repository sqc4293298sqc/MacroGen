package com.sqc.macrogen;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;

import java.io.File;
import java.io.FileNotFoundException;

/**
 * 拍照用的极简 provider：把缓存目录下的临时照片以 content:// 交给相机写。
 * 手工编译没有 androidx，所以不用 FileProvider。
 */
public class PhotoProvider extends ContentProvider {

    public static Uri uriFor(Context ctx, String fileName) {
        return Uri.parse("content://" + ctx.getPackageName() + ".photoprovider/" + fileName);
    }

    @Override
    public boolean onCreate() {
        return true;
    }

    @Override
    public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
        String name = uri.getLastPathSegment();
        if (name == null || name.contains("..") || name.contains("/")) {
            throw new FileNotFoundException("bad name");
        }
        File f = new File(getContext().getCacheDir(), name);
        int flags = mode.contains("w")
                ? ParcelFileDescriptor.MODE_CREATE | ParcelFileDescriptor.MODE_WRITE_ONLY
                : ParcelFileDescriptor.MODE_READ_ONLY;
        return ParcelFileDescriptor.open(f, flags);
    }

    @Override
    public String getType(Uri uri) {
        return "image/jpeg";
    }

    @Override
    public Cursor query(Uri uri, String[] p, String s, String[] a, String o) {
        return null;
    }

    @Override
    public Uri insert(Uri uri, ContentValues v) {
        return null;
    }

    @Override
    public int delete(Uri uri, String s, String[] a) {
        return 0;
    }

    @Override
    public int update(Uri uri, ContentValues v, String s, String[] a) {
        return 0;
    }
}

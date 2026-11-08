import SwiftUI

struct WelcomeView: View {
    @State private var entered = false
    @State private var pressed = false

    var body: some View {
        if entered {
            ContentView()
        } else {
            VStack(spacing: 0) {
                Spacer(minLength: 24)

                Image("Welcome")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 28)

                Text("宏程序生成器")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color(red: 0.106, green: 0.141, blue: 0.192))
                    .padding(.top, 26)

                Text("方形型腔 · 锥孔 · FANUC 宏程序")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(red: 0.478, green: 0.522, blue: 0.584))
                    .padding(.top, 8)

                Button {
                    entered = true
                } label: {
                    Text("进入程序")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color(red: 1.0, green: 0.420, blue: 0.102))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.top, 30)
                .padding(.horizontal, 28)

                Text("当里个当制作")
                    .font(.system(size: 17, weight: .bold))
                    .kerning(2.6)
                    .foregroundStyle(Color(red: 0.2, green: 0.251, blue: 0.31))
                    .padding(.top, 24)

                Spacer(minLength: 36)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
        }
    }
}
